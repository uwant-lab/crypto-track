import Foundation

// MARK: - Base Response

/// Bybit V5 API 공통 응답 래퍼
struct BybitResponse<T: Decodable>: Decodable {
    let retCode: Int
    let retMsg: String
    let result: T?
}

// MARK: - Wallet Balance Response

/// Bybit GET /v5/account/wallet-balance 응답 모델
struct BybitWalletResult: Decodable {
    let list: [BybitWalletAccount]
}

struct BybitWalletAccount: Decodable {
    let accountType: String
    let coin: [BybitCoinBalance]
}

struct BybitCoinBalance: Decodable {
    let coin: String
    let walletBalance: String
    let availableToWithdraw: String
    let unrealisedPnl: String?
    let cumRealisedPnl: String?
    let usdValue: String?

    var totalBalance: Double {
        Double(walletBalance) ?? 0
    }
}

// MARK: - Ticker Response

/// Bybit GET /v5/market/tickers 응답 모델
struct BybitTickerResult: Decodable {
    let category: String
    let list: [BybitTicker]
}

struct BybitTicker: Decodable {
    let symbol: String
    let lastPrice: String
    let price24hPcnt: String
    let volume24h: String
}

// MARK: - Mapping Extensions

extension BybitCoinBalance {
    /// BybitCoinBalance → 공통 Asset 모델로 변환
    func toAsset() -> Asset {
        Asset(
            id: "bybit-\(coin.lowercased())",
            symbol: coin,
            balance: totalBalance,
            averageBuyPrice: 0,
            exchange: .bybit,
            lastUpdated: Date()
        )
    }
}

extension BybitTicker {
    /// BybitTicker → 공통 Ticker 모델로 변환
    /// - Parameter baseSymbol: 거래 쌍에서 기반 코인 심볼 (예: "BTCUSDT" → "BTC")
    func toTicker(baseSymbol: String) -> Ticker {
        Ticker(
            id: "bybit-\(symbol.lowercased())",
            symbol: baseSymbol,
            currentPrice: Double(lastPrice) ?? 0,
            changeRate24h: (Double(price24hPcnt) ?? 0) * 100,
            volume24h: Double(volume24h) ?? 0,
            exchange: .bybit,
            timestamp: Date()
        )
    }
}
