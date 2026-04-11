import Foundation

/// Flat display row produced by `PortfolioAggregator`.
///
/// Works for both aggregated rows (multiple source assets folded together in the
/// "전체" filter) and single-exchange rows (one row per asset when a specific
/// exchange is selected). The `exchanges` array preserves which exchanges
/// contributed to this row so the UI can render a badge strip.
///
/// Display fields are pre-computed because SwiftUI's `Table` + `KeyPathComparator`
/// cannot sort on computed properties — every sortable value must be a flat stored
/// property on the row type.
struct PortfolioRow: Identifiable, Sendable {
    /// Stable identifier. For aggregated rows: `"<currency>-<symbol>"` (e.g. `"krw-BTC"`).
    /// For single-exchange rows: `"<exchange>-<symbol>"` (e.g. `"upbit-BTC"`).
    let id: String
    let symbol: String
    let quoteCurrency: QuoteCurrency
    /// Exchanges that contributed to this row, sorted by `Exchange.allCases` order
    /// for stable rendering.
    let exchanges: [Exchange]

    /// Sum of balances across all contributing assets.
    let totalBalance: Double
    /// Weighted average buy price. Computed from the subset of balances whose cost
    /// basis is known. Zero when no contributing asset has a cost basis.
    let averageBuyPrice: Double
    /// "Effective" current price = `currentValue / totalBalance`. Always the
    /// value-weighted average across contributing exchanges. Zero when
    /// `totalBalance == 0` or no tickers were available.
    let currentPrice: Double
    /// Σ(balance_i × ticker_i.currentPrice) across contributing assets. Assets with
    /// no matching ticker contribute 0.
    let currentValue: Double
    /// Σ(balance_i × averageBuyPrice_i) restricted to the subset of holdings whose
    /// cost basis is known. Matches the "매수금액" column in the dashboard.
    /// Zero when `hasCostBasis == false`.
    let totalCost: Double
    /// Unrealized profit restricted to the subset of holdings with a known cost basis.
    let profit: Double
    /// Profit rate (%) over the known-basis subset. Zero when `knownCost == 0`.
    let profitRate: Double
    /// Value-weighted 24h change rate across the contributing exchanges' tickers.
    /// `nil` when no contributing asset has a matching ticker. Weighting: each
    /// ticker's changeRate24h is weighted by `balance × price`, so exchanges
    /// with larger holdings dominate the aggregate.
    let changeRate24h: Double?

    /// True when at least one contributing asset has a known cost basis.
    let hasCostBasis: Bool
    /// True when some contributing assets have cost basis and others don't — the UI
    /// should display an "일부 미제공" hint.
    let hasPartialCostBasis: Bool
    /// True when at least one contributing asset has a matching ticker.
    let hasTicker: Bool
}
