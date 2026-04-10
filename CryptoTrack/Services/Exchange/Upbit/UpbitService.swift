import Foundation
import CryptoKit

// MARK: - Upbit Service

/// Upbit 거래소 API와 통신하는 서비스 구현체.
/// `ExchangeService` 프로토콜을 채택하며, JWT 인증을 사용합니다.
/// API 키는 KeychainService를 통해서만 접근합니다.
final class UpbitService: ExchangeService, Sendable {

    // MARK: - ExchangeService Properties

    let exchange: Exchange = .upbit
    let authMethod: AuthMethod = .jwt

    // MARK: - Private Properties

    private let baseURL = "https://api.upbit.com"
    private let authenticator = UpbitAuthenticator()
    private let session: URLSession

    // MARK: - Initializer

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - ExchangeService Methods

    /// 업비트 계좌의 보유 자산 목록을 조회합니다.
    /// - Throws: `UpbitServiceError` 또는 `KeychainError`
    /// - Returns: 공통 Asset 모델 배열
    func fetchAssets() async throws -> [Asset] {
        let authHeader = try authenticator.generateAuthorizationHeader()

        guard let url = URL(string: "\(baseURL)/v1/accounts") else {
            throw UpbitServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as UpbitServiceError {
            throw error
        } catch {
            throw UpbitServiceError.networkError(error)
        }

        do {
            let accounts = try JSONDecoder().decode([UpbitAccount].self, from: data)
            // KRW 원화 계좌는 자산 목록에서 제외
            return accounts
                .filter { $0.currency != "KRW" }
                .map { $0.toAsset() }
        } catch {
            throw UpbitServiceError.decodingFailed(error)
        }
    }

    /// 특정 심볼의 KRW 마켓 현재 시세를 조회합니다.
    /// - Parameter symbols: 심볼 목록 (예: ["BTC", "ETH"])
    /// - Throws: `UpbitServiceError`
    /// - Returns: 공통 Ticker 모델 배열
    func fetchTickers(symbols: [String]) async throws -> [Ticker] {
        guard !symbols.isEmpty else { return [] }

        // 심볼을 Upbit 마켓 코드로 변환: "BTC" → "KRW-BTC"
        let markets = symbols.map { "KRW-\($0)" }.joined(separator: ",")

        guard var components = URLComponents(string: "\(baseURL)/v1/ticker") else {
            throw UpbitServiceError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "markets", value: markets)]

        guard let url = components.url else {
            throw UpbitServiceError.invalidURL
        }

        // 시세 조회는 공개 API이므로 인증 불필요
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as UpbitServiceError {
            throw error
        } catch {
            throw UpbitServiceError.networkError(error)
        }

        do {
            let tickers = try JSONDecoder().decode([UpbitTicker].self, from: data)
            return tickers.map { $0.toTicker() }
        } catch {
            throw UpbitServiceError.decodingFailed(error)
        }
    }

    /// API 키의 유효성을 검증합니다.
    /// - Throws: `UpbitServiceError` 또는 `KeychainError`
    /// - Returns: 연결 성공 여부
    func validateConnection() async throws -> Bool {
        do {
            _ = try await fetchAssets()
            return true
        } catch KeychainError.itemNotFound {
            throw UpbitAuthError.missingAPIKeys
        } catch let error as UpbitServiceError {
            switch error {
            case .httpError(let statusCode) where statusCode == 401:
                return false
            default:
                throw error
            }
        }
    }

    /// 캔들스틱 데이터를 조회합니다. (공개 API)
    /// - Parameters:
    ///   - symbol: 심볼 (예: "BTC")
    ///   - timeframe: 봉 간격
    ///   - limit: 최대 조회 개수
    func fetchKlines(symbol: String, timeframe: ChartTimeframe, limit: Int) async throws -> [Kline] {
        let market = "KRW-\(symbol.uppercased())"
        let path: String
        switch timeframe {
        case .minute1:
            path = "/v1/candles/minutes/1"
        case .minute5:
            path = "/v1/candles/minutes/5"
        case .minute15:
            path = "/v1/candles/minutes/15"
        case .hour1:
            path = "/v1/candles/minutes/60"
        case .hour4:
            path = "/v1/candles/minutes/240"
        case .day1:
            path = "/v1/candles/days"
        case .week1:
            path = "/v1/candles/weeks"
        case .month1:
            path = "/v1/candles/months"
        }

        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw UpbitServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "market", value: market),
            URLQueryItem(name: "count", value: "\(limit)")
        ]
        guard let url = components.url else {
            throw UpbitServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as UpbitServiceError {
            throw error
        } catch {
            throw UpbitServiceError.networkError(error)
        }

        do {
            let klines = try JSONDecoder().decode([UpbitKline].self, from: data)
            return klines
                .map { $0.toKline(symbol: symbol.uppercased(), timeframe: timeframe) }
                .sorted { $0.timestamp < $1.timestamp }
        } catch {
            throw UpbitServiceError.decodingFailed(error)
        }
    }

    /// 체결 완료된 주문 내역을 조회합니다.
    /// Upbit API: GET /v1/orders/closed (JWT 인증, 쿼리 해시 필요)
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 100

        guard var components = URLComponents(string: "\(baseURL)/v1/orders/closed") else {
            throw UpbitServiceError.invalidURL
        }

        let queryItems = [
            URLQueryItem(name: "state", value: "done"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "order_by", value: "desc")
        ]
        components.queryItems = queryItems

        // 쿼리 해시 생성 (SHA-512)
        let queryString = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        let queryData = Data(queryString.utf8)
        let hash = SHA512.hash(data: queryData)
        let queryHash = hash.map { String(format: "%02x", $0) }.joined()

        let authHeader = try authenticator.generateAuthorizationHeader(queryHash: queryHash)

        guard let url = components.url else {
            throw UpbitServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as UpbitServiceError {
            throw error
        } catch {
            throw UpbitServiceError.networkError(error)
        }

        do {
            let orders = try JSONDecoder().decode([UpbitOrder].self, from: data)
            // 기간 필터링
            let filtered = orders.compactMap { order -> Order? in
                let mapped = order.toOrder()
                guard mapped.executedAt >= from && mapped.executedAt <= to else { return nil }
                return mapped
            }
            let hasMore = orders.count == limit
            return PagedResult(items: filtered, hasMore: hasMore, progress: nil)
        } catch {
            throw UpbitServiceError.decodingFailed(error)
        }
    }

    /// 입금 내역을 조회합니다.
    /// Upbit API: GET /v1/deposits (JWT 인증, 쿼리 해시 필요)
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 100

        guard var components = URLComponents(string: "\(baseURL)/v1/deposits") else {
            throw UpbitServiceError.invalidURL
        }

        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "order_by", value: "desc")
        ]
        components.queryItems = queryItems

        // 쿼리 해시 생성 (SHA-512)
        let queryString = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        let queryData = Data(queryString.utf8)
        let hash = SHA512.hash(data: queryData)
        let queryHash = hash.map { String(format: "%02x", $0) }.joined()

        let authHeader = try authenticator.generateAuthorizationHeader(queryHash: queryHash)

        guard let url = components.url else {
            throw UpbitServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as UpbitServiceError {
            throw error
        } catch {
            throw UpbitServiceError.networkError(error)
        }

        do {
            let deposits = try JSONDecoder().decode([UpbitDeposit].self, from: data)
            // 기간 필터링
            let filtered = deposits.compactMap { deposit -> Deposit? in
                let mapped = deposit.toDeposit()
                guard mapped.completedAt >= from && mapped.completedAt <= to else { return nil }
                return mapped
            }
            let hasMore = deposits.count == limit
            return PagedResult(items: filtered, hasMore: hasMore, progress: nil)
        } catch {
            throw UpbitServiceError.decodingFailed(error)
        }
    }

    // MARK: - Private Helpers

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpbitServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpbitServiceError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Service Errors

enum UpbitServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다."
        case .invalidResponse:
            return "서버로부터 올바르지 않은 응답을 받았습니다."
        case .httpError(let code):
            return "서버 오류가 발생했습니다. (HTTP \(code))"
        case .networkError(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "데이터 파싱에 실패했습니다: \(error.localizedDescription)"
        }
    }
}
