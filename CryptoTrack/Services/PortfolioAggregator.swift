import Foundation

/// Pure aggregation of assets + tickers into display rows.
/// Stateless enum so it can be called from any context and exercised in isolation.
enum PortfolioAggregator {

    /// Aggregates `assets` into one row per `(symbol, quoteCurrency)`. Rows from
    /// different quote currencies are never merged — a user holding BTC on Upbit
    /// (KRW) and Binance (USDT) will see two BTC rows.
    ///
    /// Tickers are matched by exact `(symbol, exchange)`. If an asset has no
    /// matching ticker, its contribution to `currentValue` is zero.
    static func aggregate(assets: [Asset], tickers: [Ticker]) -> [PortfolioRow] {
        let lookup = tickerLookup(tickers)
        let groups = Dictionary(grouping: assets) { asset in
            GroupKey(symbol: asset.symbol, quoteCurrency: asset.quoteCurrency)
        }

        return groups.map { key, groupAssets in
            makeRow(id: "\(key.quoteCurrency.rawValue)-\(key.symbol)",
                    symbol: key.symbol,
                    quoteCurrency: key.quoteCurrency,
                    groupAssets: groupAssets,
                    tickers: lookup)
        }
    }

    // MARK: - Internals

    private struct GroupKey: Hashable {
        let symbol: String
        let quoteCurrency: QuoteCurrency
    }

    private struct TickerKey: Hashable {
        let symbol: String
        let exchange: Exchange
    }

    private static func tickerLookup(_ tickers: [Ticker]) -> [TickerKey: Ticker] {
        var result: [TickerKey: Ticker] = [:]
        for t in tickers {
            result[TickerKey(symbol: t.symbol, exchange: t.exchange)] = t
        }
        return result
    }

    private static func makeRow(
        id: String,
        symbol: String,
        quoteCurrency: QuoteCurrency,
        groupAssets: [Asset],
        tickers: [TickerKey: Ticker]
    ) -> PortfolioRow {
        var totalBalance: Double = 0
        var totalValue: Double = 0
        var knownBalance: Double = 0
        var knownCost: Double = 0
        var knownValue: Double = 0
        var hasAnyTicker = false
        var contributingExchanges: Set<Exchange> = []

        for asset in groupAssets {
            contributingExchanges.insert(asset.exchange)
            totalBalance += asset.balance

            let ticker = tickers[TickerKey(symbol: asset.symbol, exchange: asset.exchange)]
            let price = ticker?.currentPrice ?? 0
            if ticker != nil { hasAnyTicker = true }
            let assetValue = asset.balance * price
            totalValue += assetValue

            if asset.hasCostBasis {
                knownBalance += asset.balance
                knownCost += asset.balance * asset.averageBuyPrice
                knownValue += assetValue
            }
        }

        let averageBuyPrice = knownBalance > 0 ? knownCost / knownBalance : 0
        let currentPrice = totalBalance > 0 ? totalValue / totalBalance : 0
        let profit = knownValue - knownCost
        let profitRate = knownCost > 0 ? (profit / knownCost) * 100 : 0

        return PortfolioRow(
            id: id,
            symbol: symbol,
            quoteCurrency: quoteCurrency,
            exchanges: Exchange.allCases.filter { contributingExchanges.contains($0) },
            totalBalance: totalBalance,
            averageBuyPrice: averageBuyPrice,
            currentPrice: currentPrice,
            currentValue: totalValue,
            profit: profit,
            profitRate: profitRate,
            hasCostBasis: knownBalance > 0,
            hasPartialCostBasis: knownBalance > 0 && knownBalance < totalBalance,
            hasTicker: hasAnyTicker
        )
    }
}
