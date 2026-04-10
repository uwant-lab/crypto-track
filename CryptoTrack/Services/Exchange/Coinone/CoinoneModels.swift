import Foundation

// MARK: - Coinone API Response Models

/// POST /v2.1/account/balance 응답 모델
struct CoinoneBalanceResponse: Decodable, Sendable {
    let result: String
    let errorCode: String?
    let balances: [CoinoneBalance]?

    enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case balances
    }
}

/// 개별 자산 잔액 모델
struct CoinoneBalance: Decodable, Sendable {
    let currency: String
    let balance: String
    let available: String
    let limitOrder: String
    let avgPrice: String

    enum CodingKeys: String, CodingKey {
        case currency
        case balance
        case available
        case limitOrder = "limit_order"
        case avgPrice = "avg_price"
    }
}

/// GET /public/v2/ticker_new/KRW/{symbol} 응답 모델
struct CoinoneTickerResponse: Decodable, Sendable {
    let result: String
    let errorCode: String?
    let tickers: [CoinoneTicker]?

    enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case tickers
    }
}

/// 개별 시세 모델
struct CoinoneTicker: Decodable, Sendable {
    let targetCurrency: String
    let last: String
    let yesterdayLast: String?
    let volume: String
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case targetCurrency = "target_currency"
        case last
        case yesterdayLast = "yesterday_last"
        case volume
        case timestamp
    }
}

// MARK: - Kline Response

/// Coinone GET /public/v2/chart/KRW/{symbol} 응답 모델
struct CoinoneChartResponse: Decodable, Sendable {
    let result: String
    let errorCode: String?
    let chart: [CoinoneCandle]?

    enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case chart
    }
}

struct CoinoneCandle: Decodable, Sendable {
    let timestamp: String
    let open: String
    let high: String
    let low: String
    let close: String
    let targetVolume: String

    enum CodingKeys: String, CodingKey {
        case timestamp
        case open
        case high
        case low
        case close
        case targetVolume = "target_volume"
    }
}

extension CoinoneCandle {
    func toKline(symbol: String, timeframe: ChartTimeframe) -> Kline {
        let ts = Double(timestamp) ?? 0
        return Kline(
            id: "coinone-\(symbol)-\(timestamp)",
            timestamp: Date(timeIntervalSince1970: ts / 1000),
            open: Double(open) ?? 0,
            high: Double(high) ?? 0,
            low: Double(low) ?? 0,
            close: Double(close) ?? 0,
            volume: Double(targetVolume) ?? 0,
            timeframe: timeframe,
            exchange: .coinone,
            symbol: symbol
        )
    }
}

// MARK: - Mapping Extensions

extension CoinoneBalance {
    /// Coinone 잔액 응답을 공통 Asset 모델로 변환합니다.
    func toAsset() -> Asset {
        let balanceValue = Double(balance) ?? 0
        let avgPrice = Double(avgPrice) ?? 0
        return Asset(
            id: "coinone-\(currency)",
            symbol: currency,
            balance: balanceValue,
            averageBuyPrice: avgPrice,
            exchange: .coinone,
            lastUpdated: Date()
        )
    }
}

extension CoinoneTicker {
    /// Coinone 시세 응답을 공통 Ticker 모델로 변환합니다.
    func toTicker() -> Ticker {
        let currentPrice = Double(last) ?? 0
        let prevClose = Double(yesterdayLast ?? "0") ?? 0
        let changeRate: Double
        if prevClose > 0 {
            changeRate = ((currentPrice - prevClose) / prevClose) * 100
        } else {
            changeRate = 0
        }
        let vol = Double(volume) ?? 0
        let ts = Double(timestamp) ?? 0
        let date = ts > 0 ? Date(timeIntervalSince1970: ts / 1000) : Date()

        return Ticker(
            id: "coinone-\(targetCurrency)",
            symbol: targetCurrency,
            currentPrice: currentPrice,
            changeRate24h: changeRate,
            volume24h: vol,
            exchange: .coinone,
            timestamp: date
        )
    }
}
