import Foundation

/// OKX 거래소 API와 통신하는 서비스 구현체.
/// `ExchangeService` 프로토콜을 채택하며 HMAC-SHA256 + 패스프레이즈 서명 인증을 사용합니다.
final class OKXService: ExchangeService {

    // MARK: - ExchangeService

    let exchange: Exchange = .okx
    let authMethod: AuthMethod = .hmacSHA256WithPassphrase

    // MARK: - Private Properties

    private let baseURL = "https://www.okx.com"
    private let authenticator: OKXAuthenticator
    private let session: URLSession

    /// 커서 기반 페이지네이션 상태
    private nonisolated(unsafe) var ordersCursor: String?
    private nonisolated(unsafe) var depositsCursor: String?

    // MARK: - Init

    init(authenticator: OKXAuthenticator = OKXAuthenticator(),
         session: URLSession = .shared) {
        self.authenticator = authenticator
        self.session = session
    }

    // MARK: - ExchangeService Implementation

    /// 보유 자산 목록을 조회합니다.
    /// OKX API: GET /api/v5/account/balance (인증 필요)
    func fetchAssets() async throws -> [Asset] {
        let path = "/api/v5/account/balance"
        let request = try buildAuthenticatedRequest(method: "GET", path: path)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OKXResponse<OKXAccountBalance>.self, from: data)

        guard decoded.isSuccess else {
            throw OKXServiceError.apiError(code: decoded.code, message: decoded.msg)
        }

        // USDT 자체는 quote currency이므로 자산 목록에서 제외한다.
        // (OKX의 fetchTickers는 전체 spot 풀 후 필터라 기술적으로는
        //  배치 실패를 일으키지 않지만, Binance/Bybit와 일관성을 맞추고
        //  대시보드에 USDT가 0원 평가액으로 나타나는 것을 막는다.)
        return decoded.data
            .flatMap { $0.details }
            .filter { $0.ccy != "USDT" }
            .filter { $0.totalBalance > 0 }
            .map { $0.toAsset() }
    }

    /// 특정 심볼의 현재 시세를 조회합니다.
    /// OKX API: GET /api/v5/market/tickers?instType=SPOT
    /// - Parameter symbols: 조회할 코인 심볼 목록 (예: ["BTC", "ETH"])
    func fetchTickers(symbols: [String]) async throws -> [Ticker] {
        let path = "/api/v5/market/tickers"
        let queryItems = [URLQueryItem(name: "instType", value: "SPOT")]
        let request = try buildRequest(path: path, queryItems: queryItems)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OKXResponse<OKXTicker>.self, from: data)

        guard decoded.isSuccess else {
            throw OKXServiceError.apiError(code: decoded.code, message: decoded.msg)
        }

        // 요청한 심볼에 해당하는 USDT 거래 쌍만 필터링합니다.
        let upperSymbols = symbols.map { $0.uppercased() }
        return decoded.data
            .filter { ticker in
                upperSymbols.contains(ticker.baseSymbol) &&
                ticker.instId.hasSuffix("-USDT")
            }
            .map { $0.toTicker() }
    }

    /// 캔들스틱 데이터를 조회합니다. (공개 API)
    /// OKX API: GET /api/v5/market/candles
    func fetchKlines(symbol: String, timeframe: ChartTimeframe, limit: Int) async throws -> [Kline] {
        let bar: String
        switch timeframe {
        case .minute1: bar = "1m"
        case .minute5: bar = "5m"
        case .minute15: bar = "15m"
        case .hour1: bar = "1H"
        case .hour4: bar = "4H"
        case .day1: bar = "1D"
        case .week1: bar = "1W"
        case .month1: bar = "1M"
        }

        let instId = symbol.uppercased() + "-USDT"
        let queryItems = [
            URLQueryItem(name: "instId", value: instId),
            URLQueryItem(name: "bar", value: bar),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        let request = try buildRequest(path: "/api/v5/market/candles", queryItems: queryItems)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OKXKlineResponse.self, from: data)
        guard decoded.isSuccess else {
            throw OKXServiceError.apiError(code: decoded.code, message: decoded.msg)
        }
        return decoded
            .toKlines(symbol: symbol.uppercased(), timeframe: timeframe)
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// API 키 유효성을 검증합니다.
    /// OKX API: GET /api/v5/account/balance 호출 성공 여부로 판단합니다.
    func validateConnection() async throws -> Bool {
        do {
            let path = "/api/v5/account/balance"
            let request = try buildAuthenticatedRequest(method: "GET", path: path)

            let (data, response) = try await session.data(for: request)
            try validateHTTPResponse(response, data: data)

            let decoded = try JSONDecoder().decode(OKXResponse<OKXAccountBalance>.self, from: data)
            guard decoded.isSuccess else {
                throw OKXServiceError.apiError(code: decoded.code, message: decoded.msg)
            }
            return true
        } catch {
            throw error
        }
    }

    var maxQueryRangeDays: Int? { 89 }

    /// 체결 완료된 주문 내역을 조회합니다.
    /// OKX API: GET /api/v5/trade/fills-history (커서 기반 페이지네이션)
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let path: String
        // 3개월 이내면 최근 API, 이전이면 아카이브 API
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        if from >= threeMonthsAgo {
            path = "/api/v5/trade/fills-history"
        } else {
            path = "/api/v5/trade/fills-history-archive"
        }

        var queryItems = [
            URLQueryItem(name: "instType", value: "SPOT"),
            URLQueryItem(name: "begin", value: "\(Int64(from.timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "end", value: "\(Int64(to.timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "limit", value: "100")
        ]

        // 첫 페이지가 아니면 커서 사용
        if page > 0, let cursor = ordersCursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "after", value: cursor))
        } else if page == 0 {
            ordersCursor = nil
        }

        let request = try buildAuthenticatedRequest(
            method: "GET",
            path: path,
            queryItems: queryItems
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OKXResponse<OKXFill>.self, from: data)
        guard decoded.isSuccess else {
            throw OKXServiceError.apiError(code: decoded.code, message: decoded.msg)
        }

        let orders = decoded.data.map { $0.toOrder() }

        // 마지막 항목의 tradeId를 다음 커서로 저장
        ordersCursor = decoded.data.last?.tradeId
        let hasMore = decoded.data.count == 100

        return PagedResult(items: orders, hasMore: hasMore, progress: nil)
    }

    /// 입금 내역을 조회합니다.
    /// OKX API: GET /api/v5/asset/deposit-history (커서 기반 페이지네이션)
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        var queryItems = [
            URLQueryItem(name: "limit", value: "100")
        ]

        // 첫 페이지가 아니면 커서 사용
        if page > 0, let cursor = depositsCursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "after", value: cursor))
        } else if page == 0 {
            depositsCursor = nil
        }

        let request = try buildAuthenticatedRequest(
            method: "GET",
            path: "/api/v5/asset/deposit-history",
            queryItems: queryItems
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OKXResponse<OKXDepositRecord>.self, from: data)
        guard decoded.isSuccess else {
            throw OKXServiceError.apiError(code: decoded.code, message: decoded.msg)
        }

        // 기간 필터링
        let deposits = decoded.data
            .map { $0.toDeposit() }
            .filter { $0.completedAt >= from && $0.completedAt <= to }

        // 마지막 항목의 depId를 다음 커서로 저장
        depositsCursor = decoded.data.last?.depId
        let hasMore = decoded.data.count == 100

        return PagedResult(items: deposits, hasMore: hasMore, progress: nil)
    }

    // MARK: - Private Helpers

    /// 인증이 필요한 URLRequest를 생성합니다.
    private func buildAuthenticatedRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: String = ""
    ) throws -> URLRequest {
        var request = try buildRequest(path: path, queryItems: queryItems)
        request.httpMethod = method

        // 쿼리 파라미터가 있으면 requestPath에 포함시킵니다.
        let requestPath: String
        if !queryItems.isEmpty,
           var components = URLComponents(string: path) {
            components.queryItems = queryItems
            requestPath = components.url?.absoluteString ?? path
        } else {
            requestPath = path
        }

        let headers = try authenticator.authHeaders(
            method: method,
            requestPath: requestPath,
            body: body
        )

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    /// URLRequest를 생성합니다.
    private func buildRequest(
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw OKXServiceError.invalidURL
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw OKXServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        return request
    }

    /// HTTP 응답 상태 코드를 검증합니다.
    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OKXServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorBody = try? JSONDecoder().decode(OKXErrorResponse.self, from: data) {
                throw OKXServiceError.apiError(code: errorBody.code, message: errorBody.msg)
            }
            throw OKXServiceError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Error Types

enum OKXServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다."
        case .invalidResponse:
            return "서버 응답을 처리할 수 없습니다."
        case .httpError(let statusCode):
            return "HTTP 오류: \(statusCode)"
        case .apiError(let code, let message):
            return "OKX API 오류 (\(code)): \(message)"
        }
    }
}

// MARK: - Error Response Model

private struct OKXErrorResponse: Decodable {
    let code: String
    let msg: String
}
