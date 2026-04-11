import Foundation

// MARK: - Coinone Service

/// Coinone 거래소 API와 통신하는 서비스 구현체.
/// `ExchangeService` 프로토콜을 채택하며, HMAC-SHA512 인증을 사용합니다.
/// API 키는 KeychainService를 통해서만 접근합니다.
final class CoinoneService: ExchangeService, Sendable {

    // MARK: - ExchangeService Properties

    let exchange: Exchange = .coinone
    let authMethod: AuthMethod = .hmacSHA512

    // MARK: - Private Properties

    private let baseURL = "https://api.coinone.co.kr"
    private let authenticator = CoinoneAuthenticator()
    private let session: URLSession

    // MARK: - Initializer

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - ExchangeService Methods

    /// Coinone 계좌의 보유 자산 목록을 조회합니다.
    /// - Throws: `CoinoneServiceError` 또는 `KeychainError`
    /// - Returns: 공통 Asset 모델 배열
    func fetchAssets() async throws -> [Asset] {
        guard let url = URL(string: "\(baseURL)/v2.1/account/balance") else {
            throw CoinoneServiceError.invalidURL
        }

        let nonce = "\(Int(Date().timeIntervalSince1970 * 1000))"

        let auth: CoinoneAuthenticator.AuthResult
        do {
            auth = try authenticator.generateAuth(payload: ["nonce": nonce])
        } catch let error as KeychainError {
            throw error
        } catch {
            throw CoinoneServiceError.authenticationFailed(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in auth.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = auth.bodyData

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.networkError(error)
        }

        do {
            let response = try JSONDecoder().decode(CoinoneBalanceResponse.self, from: data)
            guard response.result == "success" else {
                let code = response.errorCode ?? "알 수 없음"
                throw CoinoneServiceError.apiError(code)
            }
            // KRW 원화 잔액은 자산 목록에서 제외
            return (response.balances ?? [])
                .filter { $0.currency.uppercased() != "KRW" }
                .map { $0.toAsset() }
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.decodingFailed(error)
        }
    }

    /// 특정 심볼의 KRW 마켓 현재 시세를 조회합니다.
    /// - Parameter symbols: 심볼 목록 (예: ["BTC", "ETH"])
    /// - Throws: `CoinoneServiceError`
    /// - Returns: 공통 Ticker 모델 배열
    func fetchTickers(symbols: [String]) async throws -> [Ticker] {
        guard !symbols.isEmpty else { return [] }

        var tickers: [Ticker] = []
        for symbol in symbols {
            if let ticker = try await fetchSingleTicker(symbol: symbol) {
                tickers.append(ticker)
            }
        }
        return tickers
    }

    /// API 키의 유효성을 검증합니다.
    /// - Throws: `CoinoneServiceError` 또는 `KeychainError`
    /// - Returns: 연결 성공 여부
    func validateConnection() async throws -> Bool {
        do {
            _ = try await fetchAssets()
            return true
        } catch KeychainError.itemNotFound {
            throw CoinoneAuthError.missingAPIKeys
        } catch let error as CoinoneServiceError {
            switch error {
            case .httpError(let statusCode) where statusCode == 401:
                return false
            case .apiError:
                return false
            default:
                throw error
            }
        }
    }

    /// 캔들스틱 데이터를 조회합니다. (공개 API)
    /// Coinone API: GET /public/v2/chart/KRW/{symbol}
    func fetchKlines(symbol: String, timeframe: ChartTimeframe, limit: Int) async throws -> [Kline] {
        let interval: String
        switch timeframe {
        case .minute1: interval = "1m"
        case .minute5: interval = "5m"
        case .minute15: interval = "15m"
        case .hour1: interval = "1h"
        case .hour4: interval = "4h"
        case .day1: interval = "1d"
        case .week1, .month1:
            // Coinone은 주봉/월봉 미지원, 빈 배열 반환
            return []
        }

        let upperSymbol = symbol.uppercased()
        guard var components = URLComponents(string: "\(baseURL)/public/v2/chart/KRW/\(upperSymbol)") else {
            throw CoinoneServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url else {
            throw CoinoneServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.networkError(error)
        }

        do {
            let response = try JSONDecoder().decode(CoinoneChartResponse.self, from: data)
            guard response.result == "success" else {
                let code = response.errorCode ?? "알 수 없음"
                throw CoinoneServiceError.apiError(code)
            }
            return (response.chart ?? [])
                .map { $0.toKline(symbol: upperSymbol, timeframe: timeframe) }
                .sorted { $0.timestamp < $1.timestamp }
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.decodingFailed(error)
        }
    }

    /// 체결 완료된 주문 내역을 조회합니다.
    /// Coinone API: GET /v2.1/order/completed_orders
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 100
        let offset = page * limit

        guard var components = URLComponents(string: "\(baseURL)/v2.1/order/completed_orders") else {
            throw CoinoneServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url else {
            throw CoinoneServiceError.invalidURL
        }

        let nonce = "\(Int(Date().timeIntervalSince1970 * 1000))"
        let auth: CoinoneAuthenticator.AuthResult
        do {
            auth = try authenticator.generateAuth(payload: [
                "nonce": nonce,
                "offset": offset,
                "limit": limit
            ])
        } catch let error as KeychainError {
            throw error
        } catch {
            throw CoinoneServiceError.authenticationFailed(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in auth.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = auth.bodyData

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.networkError(error)
        }

        do {
            let response = try JSONDecoder().decode(CoinoneOrderResponse.self, from: data)
            guard response.result == "success" else {
                let code = response.errorCode ?? "알 수 없음"
                throw CoinoneServiceError.apiError(code)
            }
            let orders = (response.completedOrders ?? [])
                .map { $0.toOrder() }
                .filter { $0.executedAt >= from && $0.executedAt <= to }
            let hasMore = (response.completedOrders?.count ?? 0) == limit
            return PagedResult(items: orders, hasMore: hasMore, progress: nil)
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.decodingFailed(error)
        }
    }

    /// 입금 내역을 조회합니다.
    /// Coinone API: GET /v2.1/account/deposit
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 100
        let offset = page * limit

        guard var components = URLComponents(string: "\(baseURL)/v2.1/account/deposit") else {
            throw CoinoneServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url else {
            throw CoinoneServiceError.invalidURL
        }

        let nonce = "\(Int(Date().timeIntervalSince1970 * 1000))"
        let auth: CoinoneAuthenticator.AuthResult
        do {
            auth = try authenticator.generateAuth(payload: [
                "nonce": nonce,
                "offset": offset,
                "limit": limit
            ])
        } catch let error as KeychainError {
            throw error
        } catch {
            throw CoinoneServiceError.authenticationFailed(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in auth.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = auth.bodyData

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.networkError(error)
        }

        do {
            let response = try JSONDecoder().decode(CoinoneDepositResponse.self, from: data)
            guard response.result == "success" else {
                let code = response.errorCode ?? "알 수 없음"
                throw CoinoneServiceError.apiError(code)
            }
            let deposits = (response.deposits ?? [])
                .map { $0.toDeposit() }
                .filter { $0.completedAt >= from && $0.completedAt <= to }
            let hasMore = (response.deposits?.count ?? 0) == limit
            return PagedResult(items: deposits, hasMore: hasMore, progress: nil)
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.decodingFailed(error)
        }
    }

    // MARK: - Private Helpers

    private func fetchSingleTicker(symbol: String) async throws -> Ticker? {
        let upperSymbol = symbol.uppercased()
        guard let url = URL(string: "\(baseURL)/public/v2/ticker_new/KRW/\(upperSymbol)") else {
            throw CoinoneServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.networkError(error)
        }

        do {
            let response = try JSONDecoder().decode(CoinoneTickerResponse.self, from: data)
            guard response.result == "success" else {
                let code = response.errorCode ?? "알 수 없음"
                throw CoinoneServiceError.apiError(code)
            }
            return response.tickers?.first?.toTicker()
        } catch let error as CoinoneServiceError {
            throw error
        } catch {
            throw CoinoneServiceError.decodingFailed(error)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoinoneServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CoinoneServiceError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Service Errors

enum CoinoneServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
    case decodingFailed(Error)
    case authenticationFailed(Error)
    case apiError(String)

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
        case .authenticationFailed(let error):
            return "인증 처리에 실패했습니다: \(error.localizedDescription)"
        case .apiError(let code):
            return "Coinone API 오류가 발생했습니다. (코드: \(code))"
        }
    }
}
