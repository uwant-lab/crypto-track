import Foundation

// MARK: - Upbit API Response Models

/// GET /v1/accounts 응답 모델
struct UpbitAccount: Decodable, Sendable {
    let currency: String
    let balance: String
    let locked: String
    let avgBuyPrice: String
    let avgBuyPriceModified: Bool
    let unitCurrency: String

    enum CodingKeys: String, CodingKey {
        case currency
        case balance
        case locked
        case avgBuyPrice = "avg_buy_price"
        case avgBuyPriceModified = "avg_buy_price_modified"
        case unitCurrency = "unit_currency"
    }
}

/// GET /v1/ticker 응답 모델
struct UpbitTicker: Decodable, Sendable {
    let market: String
    let tradePrice: Double
    let signedChangeRate: Double
    let accTradeVolume24h: Double
    let timestamp: Int64

    enum CodingKeys: String, CodingKey {
        case market
        case tradePrice = "trade_price"
        case signedChangeRate = "signed_change_rate"
        case accTradeVolume24h = "acc_trade_volume_24h"
        case timestamp
    }
}

// MARK: - Kline (GET /v1/candles/...)

/// Upbit 캔들스틱 응답 모델
struct UpbitKline: Decodable, Sendable {
    let candleDateTimeKst: String
    let openingPrice: Double
    let highPrice: Double
    let lowPrice: Double
    let tradePrice: Double
    let candleAccTradeVolume: Double
    let timestamp: Int64

    enum CodingKeys: String, CodingKey {
        case candleDateTimeKst = "candle_date_time_kst"
        case openingPrice = "opening_price"
        case highPrice = "high_price"
        case lowPrice = "low_price"
        case tradePrice = "trade_price"
        case candleAccTradeVolume = "candle_acc_trade_volume"
        case timestamp
    }
}

// MARK: - Mapping Extensions

extension UpbitAccount {
    /// Upbit 계좌 응답을 공통 Asset 모델로 변환합니다.
    func toAsset() -> Asset {
        let balanceValue = Double(balance) ?? 0
        let avgPrice = Double(avgBuyPrice) ?? 0
        return Asset(
            id: "upbit-\(currency)",
            symbol: currency,
            balance: balanceValue,
            averageBuyPrice: avgPrice,
            exchange: .upbit,
            lastUpdated: Date()
        )
    }
}

extension UpbitTicker {
    /// Upbit 시세 응답을 공통 Ticker 모델로 변환합니다.
    func toTicker() -> Ticker {
        // market 형식: "KRW-BTC" → symbol: "BTC"
        let symbol = market.split(separator: "-").last.map(String.init) ?? market
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        return Ticker(
            id: "upbit-\(market)",
            symbol: symbol,
            currentPrice: tradePrice,
            changeRate24h: signedChangeRate * 100,
            volume24h: accTradeVolume24h,
            exchange: .upbit,
            timestamp: date
        )
    }
}

extension UpbitKline {
    /// Upbit 캔들 응답을 공통 Kline 모델로 변환합니다.
    func toKline(symbol: String, timeframe: ChartTimeframe) -> Kline {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        return Kline(
            id: "upbit-\(symbol)-\(timestamp)",
            timestamp: date,
            open: openingPrice,
            high: highPrice,
            low: lowPrice,
            close: tradePrice,
            volume: candleAccTradeVolume,
            timeframe: timeframe,
            exchange: .upbit,
            symbol: symbol
        )
    }
}
