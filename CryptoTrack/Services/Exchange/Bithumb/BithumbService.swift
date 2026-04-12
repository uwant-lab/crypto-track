import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "com.cryptotrack", category: "Bithumb")

// MARK: - Bithumb Service

/// 빗썸 거래소 API 2.0 (v1 엔드포인트)와 통신하는 서비스 구현체.
/// `ExchangeService` 프로토콜을 채택하며, JWT(HS256) 인증을 사용합니다.
/// API 키는 KeychainService를 통해서만 접근합니다.
final class BithumbService: ExchangeService, Sendable {

    // MARK: - ExchangeService Properties

    let exchange: Exchange = .bithumb
    let authMethod: AuthMethod = .jwt

    // MARK: - Private Properties

    private let baseURL = "https://api.bithumb.com"
    private let authenticator = BithumbAuthenticator()
    private let session: URLSession

    // MARK: - Initializer

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - ExchangeService Methods

    /// 빗썸 계좌의 보유 자산 목록을 조회합니다.
    /// - Throws: `BithumbServiceError` 또는 `KeychainError`
    /// - Returns: 공통 Asset 모델 배열
    func fetchAssets() async throws -> [Asset] {
        let authHeader = try authenticator.generateAuthorizationHeader()

        guard let url = URL(string: "\(baseURL)/v1/accounts") else {
            throw BithumbServiceError.invalidURL
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
        } catch let error as BithumbServiceError {
            throw error
        } catch {
            throw BithumbServiceError.networkError(error)
        }

        do {
            let accounts = try JSONDecoder().decode([BithumbAccount].self, from: data)
            // KRW 원화 계좌는 자산 목록에서 제외
            return accounts
                .filter { $0.currency != "KRW" }
                .map { $0.toAsset() }
        } catch {
            throw BithumbServiceError.decodingFailed(error)
        }
    }

    /// 특정 심볼의 KRW 마켓 현재 시세를 조회합니다.
    ///
    /// 빗썸의 `/v1/ticker?markets=A,B,C` 배치 엔드포인트는 **하나의 심볼이라도
    /// KRW 마켓에 존재하지 않으면 전체 응답을 `{"error":{"name":404, ...}}`
    /// 로 대체**해 버린다 (HTTP 200). 상장 폐지되었거나 원래 KRW 페어가
    /// 없는 코인이 사용자 잔고에 섞여 있으면 전체 시세가 날아가므로,
    /// 배치 실패 시 심볼별 병렬 호출로 폴백해 유효한 티커만 모은다.
    ///
    /// - Parameter symbols: 심볼 목록 (예: ["BTC", "ETH"])
    /// - Returns: 성공한 심볼의 Ticker 배열 (빈 배열 허용).
    func fetchTickers(symbols: [String]) async throws -> [Ticker] {
        guard !symbols.isEmpty else { return [] }

        // 1) 배치 호출 시도 (happy path).
        if let batch = try? await fetchTickersBatch(symbols: symbols) {
            return batch
        }

        // 2) Fallback: 심볼별 병렬 호출. 개별 심볼의 404는 조용히 드롭한다.
        return await fetchTickersIndividually(symbols: symbols)
    }

    /// 빗썸 배치 ticker 엔드포인트를 한 번의 HTTP 호출로 쏜다.
    /// 하나라도 존재하지 않는 마켓이 섞이면 `.decodingFailed`로 throw한다.
    private func fetchTickersBatch(symbols: [String]) async throws -> [Ticker] {
        // 심볼을 빗썸 마켓 코드로 변환: "BTC" → "KRW-BTC"
        let markets = symbols.map { "KRW-\($0)" }.joined(separator: ",")

        guard var components = URLComponents(string: "\(baseURL)/v1/ticker") else {
            throw BithumbServiceError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "markets", value: markets)]

        guard let url = components.url else {
            throw BithumbServiceError.invalidURL
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
        } catch let error as BithumbServiceError {
            throw error
        } catch {
            throw BithumbServiceError.networkError(error)
        }

        // 빗썸은 상장폐지/미상장 심볼이 섞이면 HTTP 200 + `{"error":{...}}`를
        // 돌려준다. 배열 디코딩이 실패하면 throw해서 fallback 경로로 넘긴다.
        do {
            let tickers = try JSONDecoder().decode([BithumbTicker].self, from: data)
            return tickers.map { $0.toTicker() }
        } catch {
            throw BithumbServiceError.decodingFailed(error)
        }
    }

    /// 심볼을 한 개씩 병렬로 조회한다. 개별 호출 실패는 nil로 처리하고,
    /// 성공한 티커만 모아 반환한다. 절대 throw하지 않는다.
    private func fetchTickersIndividually(symbols: [String]) async -> [Ticker] {
        await withTaskGroup(of: Ticker?.self) { group in
            for symbol in symbols {
                group.addTask {
                    do {
                        let batch = try await self.fetchTickersBatch(symbols: [symbol])
                        return batch.first
                    } catch {
                        return nil
                    }
                }
            }
            var collected: [Ticker] = []
            for await ticker in group {
                if let ticker { collected.append(ticker) }
            }
            return collected
        }
    }

    /// API 키의 유효성을 검증합니다.
    /// - Throws: `BithumbServiceError` 또는 `KeychainError`
    /// - Returns: 연결 성공 여부
    func validateConnection() async throws -> Bool {
        do {
            _ = try await fetchAssets()
            return true
        } catch KeychainError.itemNotFound {
            throw BithumbAuthError.missingAPIKeys
        } catch let error as BithumbServiceError {
            switch error {
            case .httpError(let statusCode) where statusCode == 401:
                return false
            default:
                throw error
            }
        }
    }

    /// 캔들스틱 데이터를 조회합니다. (공개 API)
    /// 빗썸 API: GET /v1/candles/...
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
            throw BithumbServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "market", value: market),
            URLQueryItem(name: "count", value: "\(limit)")
        ]
        guard let url = components.url else {
            throw BithumbServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as BithumbServiceError {
            throw error
        } catch {
            throw BithumbServiceError.networkError(error)
        }

        do {
            let klines = try JSONDecoder().decode([BithumbKline].self, from: data)
            return klines
                .map { $0.toKline(symbol: symbol.uppercased(), timeframe: timeframe) }
                .sorted { $0.timestamp < $1.timestamp }
        } catch {
            throw BithumbServiceError.decodingFailed(error)
        }
    }

    /// 체결 완료된 주문 내역을 조회합니다.
    /// 빗썸 API: GET /v1/orders (JWT 인증, 쿼리 해시 필요)
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 100

        guard var components = URLComponents(string: "\(baseURL)/v1/orders") else {
            throw BithumbServiceError.invalidURL
        }

        let apiPage = page + 1
        let queryItems = [
            URLQueryItem(name: "state", value: "done"),
            URLQueryItem(name: "page", value: "\(apiPage)"),
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
            throw BithumbServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response, data: responseData)
            data = responseData
        } catch let error as BithumbServiceError {
            throw error
        } catch {
            throw BithumbServiceError.networkError(error)
        }

        do {
            let rawOrders = try JSONDecoder().decode([BithumbOrder].self, from: data)
            let mapped = rawOrders.map { $0.toOrder() }
            let filtered = mapped.filter { $0.executedAt >= from && $0.executedAt <= to }
            let passedRange = mapped.last.map { $0.executedAt < from } ?? false
            let hasMore = rawOrders.count == limit && !passedRange
            return PagedResult(items: filtered, hasMore: hasMore, progress: nil)
        } catch {
            throw BithumbServiceError.decodingFailed(error)
        }
    }

    /// 입금 내역을 조회합니다.
    /// 빗썸 API: GET /v1/deposits (JWT 인증, 쿼리 해시 필요)
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 100

        guard var components = URLComponents(string: "\(baseURL)/v1/deposits") else {
            throw BithumbServiceError.invalidURL
        }

        let apiPage = page + 1
        let queryItems = [
            URLQueryItem(name: "page", value: "\(apiPage)"),
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
            throw BithumbServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response, data: responseData)
            data = responseData
        } catch let error as BithumbServiceError {
            throw error
        } catch {
            throw BithumbServiceError.networkError(error)
        }

        do {
            let rawDeposits = try JSONDecoder().decode([BithumbDeposit].self, from: data)
            let mapped = rawDeposits.map { $0.toDeposit() }
            let filtered = mapped.filter { $0.completedAt >= from && $0.completedAt <= to }
            let passedRange = mapped.last.map { $0.completedAt < from } ?? false
            let hasMore = rawDeposits.count == limit && !passedRange
            return PagedResult(items: filtered, hasMore: hasMore, progress: nil)
        } catch {
            throw BithumbServiceError.decodingFailed(error)
        }
    }

    // MARK: - Private Helpers

    private func validateHTTPResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BithumbServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let data, let body = String(data: data, encoding: .utf8) {
                logger.error("HTTP \(httpResponse.statusCode) — \(body)")
            }
            throw BithumbServiceError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Service Errors

enum BithumbServiceError: LocalizedError {
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
