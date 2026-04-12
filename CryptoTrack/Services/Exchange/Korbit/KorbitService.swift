import Foundation

// MARK: - Korbit Service

/// Korbit 거래소 API와 통신하는 서비스 구현체.
/// `ExchangeService` 프로토콜을 채택하며, OAuth 2.0 Bearer 토큰 인증을 사용합니다.
/// API 키는 KeychainService를 통해서만 접근합니다.
final class KorbitService: ExchangeService, Sendable {

    // MARK: - ExchangeService Properties

    let exchange: Exchange = .korbit
    let authMethod: AuthMethod = .oauth2

    // MARK: - Private Properties

    private let baseURL = "https://api.korbit.co.kr"
    private let authenticator = KorbitAuthenticator()
    private let session: URLSession

    // MARK: - Initializer

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - ExchangeService Methods

    /// 코빗 계좌의 보유 자산 목록을 조회합니다.
    /// - Throws: `KorbitServiceError` 또는 `KorbitAuthError`
    /// - Returns: 공통 Asset 모델 배열
    func fetchAssets() async throws -> [Asset] {
        let authHeader = try await authenticator.authorizationHeader()

        guard let url = URL(string: "\(baseURL)/v1/user/balances") else {
            throw KorbitServiceError.invalidURL
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
        } catch let error as KorbitServiceError {
            throw error
        } catch let error as KorbitAuthError {
            throw error
        } catch {
            throw KorbitServiceError.networkError(error)
        }

        do {
            let balances = try JSONDecoder().decode(KorbitBalancesResponse.self, from: data)
            // KRW 원화 잔고는 자산 목록에서 제외
            return balances
                .filter { $0.key.lowercased() != "krw" }
                .compactMap { symbol, balance -> Asset? in
                    let balanceValue = Double(balance.available) ?? 0
                    guard balanceValue > 0 else { return nil }
                    return balance.toAsset(symbol: symbol)
                }
                .sorted { $0.symbol < $1.symbol }
        } catch {
            throw KorbitServiceError.decodingFailed(error)
        }
    }

    /// 특정 심볼의 KRW 마켓 현재 시세를 조회합니다.
    /// - Parameter symbols: 심볼 목록 (예: ["BTC", "ETH"])
    /// - Throws: `KorbitServiceError`
    /// - Returns: 공통 Ticker 모델 배열
    func fetchTickers(symbols: [String]) async throws -> [Ticker] {
        guard !symbols.isEmpty else { return [] }

        var tickers: [Ticker] = []

        for symbol in symbols {
            // Korbit 통화쌍 형식: "BTC" → "btc_krw"
            let currencyPair = "\(symbol.lowercased())_krw"

            guard var components = URLComponents(string: "\(baseURL)/v1/ticker/detailed") else {
                throw KorbitServiceError.invalidURL
            }
            components.queryItems = [URLQueryItem(name: "currency_pair", value: currencyPair)]

            guard let url = components.url else {
                throw KorbitServiceError.invalidURL
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
            } catch let error as KorbitServiceError {
                throw error
            } catch {
                throw KorbitServiceError.networkError(error)
            }

            do {
                let tickerResponse = try JSONDecoder().decode(KorbitTickerResponse.self, from: data)
                tickers.append(tickerResponse.toTicker(currencyPair: currencyPair))
            } catch {
                throw KorbitServiceError.decodingFailed(error)
            }
        }

        return tickers
    }

    /// API 토큰의 유효성을 검증합니다.
    /// - Throws: `KorbitServiceError` 또는 `KorbitAuthError`
    /// - Returns: 연결 성공 여부
    func validateConnection() async throws -> Bool {
        do {
            _ = try await fetchAssets()
            return true
        } catch KeychainError.itemNotFound {
            throw KorbitAuthError.missingAPIKeys
        } catch let error as KorbitServiceError {
            switch error {
            case .httpError(let statusCode) where statusCode == 401:
                return false
            default:
                throw error
            }
        }
    }

    /// 체결 완료된 주문 내역을 조회합니다.
    /// Korbit API: GET /v1/user/orders (Bearer 토큰 인증)
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 40
        let offset = page * limit

        let authHeader = try await authenticator.authorizationHeader()

        guard var components = URLComponents(string: "\(baseURL)/v1/user/orders") else {
            throw KorbitServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "status", value: "filled"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url else {
            throw KorbitServiceError.invalidURL
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
        } catch let error as KorbitServiceError {
            throw error
        } catch let error as KorbitAuthError {
            throw error
        } catch {
            throw KorbitServiceError.networkError(error)
        }

        do {
            let rawOrders = try JSONDecoder().decode([KorbitOrder].self, from: data)
            let mapped = rawOrders.map { $0.toOrder() }
            let filtered = mapped.filter { $0.executedAt >= from && $0.executedAt <= to }
            let passedRange = mapped.last.map { $0.executedAt < from } ?? false
            let hasMore = rawOrders.count == limit && !passedRange
            return PagedResult(items: filtered, hasMore: hasMore, progress: nil)
        } catch {
            throw KorbitServiceError.decodingFailed(error)
        }
    }

    /// 입금 내역을 조회합니다.
    /// Korbit API: GET /v1/user/transfers (Bearer 토큰 인증)
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 40
        let offset = page * limit

        let authHeader = try await authenticator.authorizationHeader()

        guard var components = URLComponents(string: "\(baseURL)/v1/user/transfers") else {
            throw KorbitServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "type", value: "deposit"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url else {
            throw KorbitServiceError.invalidURL
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
        } catch let error as KorbitServiceError {
            throw error
        } catch let error as KorbitAuthError {
            throw error
        } catch {
            throw KorbitServiceError.networkError(error)
        }

        do {
            let rawTransfers = try JSONDecoder().decode([KorbitTransfer].self, from: data)
            let mapped = rawTransfers.map { $0.toDeposit() }
            let filtered = mapped.filter { $0.completedAt >= from && $0.completedAt <= to }
            let passedRange = mapped.last.map { $0.completedAt < from } ?? false
            let hasMore = rawTransfers.count == limit && !passedRange
            return PagedResult(items: filtered, hasMore: hasMore, progress: nil)
        } catch {
            throw KorbitServiceError.decodingFailed(error)
        }
    }

    /// 캔들스틱 데이터 조회 — Korbit은 캔들 API 미지원
    func fetchKlines(symbol: String, timeframe: ChartTimeframe, limit: Int) async throws -> [Kline] {
        throw KorbitServiceError.unsupportedOperation("Korbit은 캔들스틱 API를 지원하지 않습니다.")
    }

    // MARK: - Private Helpers

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KorbitServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw KorbitServiceError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Service Errors

enum KorbitServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
    case decodingFailed(Error)
    case unsupportedOperation(String)

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
        case .unsupportedOperation(let message):
            return message
        }
    }
}
