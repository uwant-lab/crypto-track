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
