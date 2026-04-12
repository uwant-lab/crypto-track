import Foundation

/// Binance 거래소 API와 통신하는 서비스 구현체.
/// `ExchangeService` 프로토콜을 채택하며 HMAC-SHA256 서명 인증을 사용합니다.
final class BinanceService: ExchangeService {

    // MARK: - ExchangeService

    let exchange: Exchange = .binance
    let authMethod: AuthMethod = .hmacSHA256

    // MARK: - Private Properties

    private let baseURL = "https://api.binance.com"
    private let authenticator: BinanceAuthenticator
    private let session: URLSession

    // MARK: - Init

    init(authenticator: BinanceAuthenticator = BinanceAuthenticator(),
         session: URLSession = .shared) {
        self.authenticator = authenticator
        self.session = session
    }

    // MARK: - ExchangeService Implementation

    /// 보유 자산 목록을 조회합니다.
    /// Binance API: GET /api/v3/account (서명 필요)
    func fetchAssets() async throws -> [Asset] {
        let signedItems = try authenticator.signedQueryItems(from: [])
        let request = try buildRequest(
            path: "/api/v3/account",
            queryItems: signedItems,
            requiresAPIKey: true
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let accountResponse = try JSONDecoder().decode(BinanceAccountResponse.self, from: data)

        // USDT 자체는 quote currency이므로 자산 목록에서 제외한다.
        // (Upbit/Bithumb가 KRW를 걸러내는 것과 대칭)
        // 포함 시 fetchTickers 배치 호출에 "USDTUSDT"라는 존재하지 않는
        // 거래쌍이 섞여 Binance API가 400을 반환하며 전체 배치가 실패한다.
        return accountResponse.balances
            .filter { $0.asset != "USDT" }
            .filter { $0.totalBalance > 0 }
            .map { $0.toAsset() }
    }

    /// 특정 심볼의 24시간 시세를 조회합니다.
    /// Binance API: GET /api/v3/ticker/24hr
    /// - Parameter symbols: 조회할 코인 심볼 목록 (예: ["BTC", "ETH"])
    func fetchTickers(symbols: [String]) async throws -> [Ticker] {
        // Defensive: USDT는 quote currency이므로 "USDTUSDT" 거래쌍이 없고,
        // 포함되면 Binance API가 400을 반환해 배치 전체가 실패한다.
        // 호출자(DashboardViewModel)가 이미 걸러내지만 서비스 레이어에서도
        // 방어한다.
        let filtered = symbols.filter { $0.uppercased() != "USDT" }
        guard !filtered.isEmpty else { return [] }

        // Binance 거래 쌍 형식으로 변환 (예: "BTC" → "BTCUSDT")
        let tradingPairs = filtered.map { $0.uppercased() + "USDT" }

        // 단일 심볼이면 단건 조회, 복수면 배열 조회
        if tradingPairs.count == 1, let pair = tradingPairs.first {
            return try await fetchSingleTicker(symbol: pair, baseSymbol: filtered[0].uppercased())
        } else {
            return try await fetchMultipleTickers(pairs: tradingPairs, baseSymbols: filtered.map { $0.uppercased() })
        }
    }

    /// 캔들스틱 데이터를 조회합니다. (공개 API)
    /// Binance API: GET /api/v3/klines
    func fetchKlines(symbol: String, timeframe: ChartTimeframe, limit: Int) async throws -> [Kline] {
        let interval: String
        switch timeframe {
        case .minute1: interval = "1m"
        case .minute5: interval = "5m"
        case .minute15: interval = "15m"
        case .hour1: interval = "1h"
        case .hour4: interval = "4h"
        case .day1: interval = "1d"
        case .week1: interval = "1w"
        case .month1: interval = "1M"
        }

        let tradingPair = symbol.uppercased() + "USDT"
        let queryItems = [
            URLQueryItem(name: "symbol", value: tradingPair),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        let request = try buildRequest(path: "/api/v3/klines", queryItems: queryItems)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let rows = try JSONDecoder().decode([[JSONValue]].self, from: data)
        return rows
            .compactMap { BinanceKline.parse(from: $0) }
            .map { $0.toKline(symbol: symbol.uppercased(), timeframe: timeframe) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// API 키 유효성을 검증합니다.
    /// Binance API: GET /api/v3/account 호출 성공 여부로 판단합니다.
    func validateConnection() async throws -> Bool {
        do {
            let signedItems = try authenticator.signedQueryItems(from: [])
            let request = try buildRequest(
                path: "/api/v3/account",
                queryItems: signedItems,
                requiresAPIKey: true
            )

            let (data, response) = try await session.data(for: request)
            try validateHTTPResponse(response, data: data)
            return true
        } catch {
            throw error
        }
    }

    var maxQueryRangeDays: Int? { 89 }

    /// 체결 완료된 주문 내역을 조회합니다.
    /// Binance API: GET /api/v3/myTrades (심볼별 조회 필요)
    /// page는 현재 심볼 인덱스로 사용됩니다.
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        // 먼저 보유 자산 목록을 조회하여 심볼 목록을 가져옵니다
        let assets = try await fetchAssets()
        let symbols = assets.map { $0.symbol.uppercased() + "USDT" }

        guard !symbols.isEmpty else {
            return PagedResult(items: [], hasMore: false, progress: nil)
        }

        // page는 심볼 인덱스 (0-based)
        guard page < symbols.count else {
            return PagedResult(items: [], hasMore: false, progress: nil)
        }

        let symbol = symbols[page]
        let startTime = Int64(from.timeIntervalSince1970 * 1000)
        let endTime = Int64(to.timeIntervalSince1970 * 1000)

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "startTime", value: "\(startTime)"),
            URLQueryItem(name: "endTime", value: "\(endTime)"),
            URLQueryItem(name: "limit", value: "1000")
        ]

        let signedItems = try authenticator.signedQueryItems(from: queryItems)
        let request = try buildRequest(
            path: "/api/v3/myTrades",
            queryItems: signedItems,
            requiresAPIKey: true
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let trades = try JSONDecoder().decode([BinanceTrade].self, from: data)
        let orders = trades.map { $0.toOrder() }
        let hasMore = (page + 1) < symbols.count
        let progress = Double(page + 1) / Double(symbols.count)

        return PagedResult(items: orders, hasMore: hasMore, progress: progress)
    }

    /// 입금 내역을 조회합니다.
    /// Binance API: GET /sapi/v1/capital/deposit/hisrec
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 1000
        let offset = page * limit
        let startTime = Int64(from.timeIntervalSince1970 * 1000)
        let endTime = Int64(to.timeIntervalSince1970 * 1000)

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "startTime", value: "\(startTime)"),
            URLQueryItem(name: "endTime", value: "\(endTime)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        let signedItems = try authenticator.signedQueryItems(from: queryItems)
        let request = try buildRequest(
            path: "/sapi/v1/capital/deposit/hisrec",
            queryItems: signedItems,
            requiresAPIKey: true
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let deposits = try JSONDecoder().decode([BinanceDeposit].self, from: data)
        let mapped = deposits.map { $0.toDeposit() }
        let hasMore = deposits.count == limit

        return PagedResult(items: mapped, hasMore: hasMore, progress: nil)
    }

    // MARK: - Private Helpers

    private func fetchSingleTicker(symbol: String, baseSymbol: String) async throws -> [Ticker] {
        let queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        let request = try buildRequest(path: "/api/v3/ticker/24hr", queryItems: queryItems)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let ticker = try JSONDecoder().decode(BinanceTicker.self, from: data)
        return [ticker.toTicker(baseSymbol: baseSymbol)]
    }

    private func fetchMultipleTickers(pairs: [String], baseSymbols: [String]) async throws -> [Ticker] {
        // Binance API는 symbols 파라미터에 JSON 배열 형식을 사용합니다
        let symbolsJSON = "[\"" + pairs.joined(separator: "\",\"") + "\"]"
        let queryItems = [URLQueryItem(name: "symbols", value: symbolsJSON)]
        let request = try buildRequest(path: "/api/v3/ticker/24hr", queryItems: queryItems)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let tickers = try JSONDecoder().decode([BinanceTicker].self, from: data)

        return tickers.map { ticker in
            // 거래 쌍에서 기반 심볼 추출 (BTCUSDT → BTC)
            let baseSymbol = baseSymbols.first {
                ticker.symbol.hasPrefix($0)
            } ?? ticker.symbol
            return ticker.toTicker(baseSymbol: baseSymbol)
        }
    }

    /// URLRequest를 생성합니다.
    private func buildRequest(
        path: String,
        queryItems: [URLQueryItem],
        requiresAPIKey: Bool = false
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw BinanceServiceError.invalidURL
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw BinanceServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        if requiresAPIKey {
            let apiKey = try authenticator.apiKey()
            request.setValue(apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        }

        return request
    }

    /// HTTP 응답 상태 코드를 검증합니다.
    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinanceServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            // Binance 오류 응답 파싱 시도
            if let errorBody = try? JSONDecoder().decode(BinanceErrorResponse.self, from: data) {
                throw BinanceServiceError.apiError(code: errorBody.code, message: errorBody.msg)
            }
            throw BinanceServiceError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Error Types

enum BinanceServiceError: LocalizedError {
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
            return "Binance API 오류 (\(code)): \(message)"
        }
    }
}

// MARK: - Error Response Model

private struct BinanceErrorResponse: Decodable {
    let code: Int
    let msg: String
}
