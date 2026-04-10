import Foundation

// MARK: - Account Response

/// Binance GET /api/v3/account 응답 모델
struct BinanceAccountResponse: Decodable {
    let balances: [BinanceBalance]
}

struct BinanceBalance: Decodable {
    let asset: String
    let free: String
    let locked: String

    /// 실제 보유 수량 (free + locked)
    var totalBalance: Double {
        (Double(free) ?? 0) + (Double(locked) ?? 0)
    }
}

// MARK: - Ticker Response

/// Binance GET /api/v3/ticker/24hr 응답 모델
struct BinanceTicker: Decodable {
    let symbol: String
    let lastPrice: String
    let priceChangePercent: String
    let volume: String
}

// MARK: - Mapping Extensions

extension BinanceBalance {
    /// BinanceBalance → 공통 Asset 모델로 변환
    func toAsset() -> Asset {
        Asset(
            id: "binance-\(asset.lowercased())",
            symbol: asset,
            balance: totalBalance,
            averageBuyPrice: 0,
            exchange: .binance,
            lastUpdated: Date()
        )
    }
}

extension BinanceTicker {
    /// BinanceTicker → 공통 Ticker 모델로 변환
    /// - Parameter baseSymbol: 거래 쌍에서 기반 코인 심볼 추출 (예: "BTCUSDT" → "BTC")
    func toTicker(baseSymbol: String) -> Ticker {
        Ticker(
            id: "binance-\(symbol.lowercased())",
            symbol: baseSymbol,
            currentPrice: Double(lastPrice) ?? 0,
            changeRate24h: Double(priceChangePercent) ?? 0,
            volume24h: Double(volume) ?? 0,
            exchange: .binance,
            timestamp: Date()
        )
    }
}
