import Foundation

/// Bybit 거래소 API와 통신하는 서비스 구현체.
/// `ExchangeService` 프로토콜을 채택하며 HMAC-SHA256 서명 인증을 사용합니다.
final class BybitService: ExchangeService {

    // MARK: - ExchangeService

    let exchange: Exchange = .bybit
    let authMethod: AuthMethod = .hmacSHA256

    // MARK: - Private Properties

    private let baseURL = "https://api.bybit.com"
    private let authenticator: BybitAuthenticator
    private let session: URLSession

    // MARK: - Init

    init(authenticator: BybitAuthenticator = BybitAuthenticator(),
         session: URLSession = .shared) {
        self.authenticator = authenticator
        self.session = session
    }

    // MARK: - ExchangeService Implementation

    /// 보유 자산 목록을 조회합니다.
    /// Bybit API: GET /v5/account/wallet-balance?accountType=UNIFIED (서명 필요)
    func fetchAssets() async throws -> [Asset] {
        let queryString = "accountType=UNIFIED"
        let request = try buildAuthenticatedRequest(
            path: "/v5/account/wallet-balance",
            queryString: queryString
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(BybitResponse<BybitWalletResult>.self, from: data)
        try validateRetCode(decoded.retCode, message: decoded.retMsg)

        guard let result = decoded.result else {
            return []
        }

        return result.list
            .flatMap { $0.coin }
            .filter { $0.totalBalance > 0 }
            .map { $0.toAsset() }
    }

    /// 특정 심볼의 현재 시세를 조회합니다.
    /// Bybit API: GET /v5/market/tickers?category=spot&symbol=BTCUSDT
    /// - Parameter symbols: 조회할 코인 심볼 목록 (예: ["BTC", "ETH"])
    func fetchTickers(symbols: [String]) async throws -> [Ticker] {
        var tickers: [Ticker] = []

        for symbol in symbols {
            let tradingPair = symbol.uppercased() + "USDT"
            let queryString = "category=spot&symbol=\(tradingPair)"
            let request = try buildRequest(
                path: "/v5/market/tickers",
                queryString: queryString
            )

            let (data, response) = try await session.data(for: request)
            try validateHTTPResponse(response, data: data)

            let decoded = try JSONDecoder().decode(BybitResponse<BybitTickerResult>.self, from: data)
            try validateRetCode(decoded.retCode, message: decoded.retMsg)

            if let result = decoded.result {
                let mapped = result.list.map { $0.toTicker(baseSymbol: symbol.uppercased()) }
                tickers.append(contentsOf: mapped)
            }
        }

        return tickers
    }

    /// API 키 유효성을 검증합니다.
    /// Bybit API: GET /v5/account/wallet-balance 호출 성공 여부로 판단합니다.
    func validateConnection() async throws -> Bool {
        let queryString = "accountType=UNIFIED"
        let request = try buildAuthenticatedRequest(
            path: "/v5/account/wallet-balance",
            queryString: queryString
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(BybitResponse<BybitWalletResult>.self, from: data)
        try validateRetCode(decoded.retCode, message: decoded.retMsg)

        return true
    }

    // MARK: - Private Helpers

    /// 인증 헤더가 포함된 URLRequest를 생성합니다. (인증 필요 엔드포인트용)
    private func buildAuthenticatedRequest(
        path: String,
        queryString: String
    ) throws -> URLRequest {
        let headers = try authenticator.authHeaders(queryString: queryString)
        return try buildRequest(path: path, queryString: queryString, additionalHeaders: headers)
    }

    /// URLRequest를 생성합니다.
    private func buildRequest(
        path: String,
        queryString: String,
        additionalHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        let urlString = baseURL + path + (queryString.isEmpty ? "" : "?" + queryString)
        guard let url = URL(string: urlString) else {
            throw BybitServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    /// HTTP 응답 상태 코드를 검증합니다.
    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BybitServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BybitServiceError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// Bybit API retCode를 검증합니다. (0이 아니면 오류)
    private func validateRetCode(_ retCode: Int, message: String) throws {
        guard retCode == 0 else {
            throw BybitServiceError.apiError(code: retCode, message: message)
        }
    }
}

// MARK: - Error Types

enum BybitServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다."
        case .invalidResponse:
            return "서버 응답을 처리할 수 없습니다."
        case .httpError(let statusCode):
            return "HTTP 오류: \(statusCode)"
        case .apiError(let code, let message):
            return "Bybit API 오류 (\(code)): \(message)"
        }
    }
}
