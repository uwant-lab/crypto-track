# Dashboard Fix & Aggregation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the dashboard ticker-scoping bug, add per-currency aggregation for the "전체" filter, and replace flat exchange text labels with a logo-or-monogram badge system.

**Architecture:** Split aggregation logic into a pure `PortfolioAggregator` (easy to test), scope ticker fetches per-exchange to stop cross-contamination, teach `DashboardViewModel` to emit `[RowSection]` grouped by `QuoteCurrency`, and render two stacked `Table`s on macOS / `Section`-based `List` on iOS. Brand badges use a hybrid: bundled SVG assets if present, brand-colored monogram circles otherwise.

**Tech Stack:** Swift 6.0, SwiftUI (iOS 17 / macOS 14 targets), XCTest, XcodeGen (`project.yml`).

**Spec:** `docs/superpowers/specs/2026-04-11-dashboard-fix-and-aggregation-design.md`

---

## Before You Start

- Read the spec in full before touching code. Every design decision (known-only weighted average, value-weighted display price, quoteCurrency section boundary) is explained there.
- Working branch is `feature/dashboard-revamp`. Do **not** switch branches.
- The project uses XcodeGen. After editing or adding source files run `xcodegen generate` before building.
- `DashboardViewModel` is `@MainActor`. `PortfolioAggregator` is a pure enum (stateless, thread-safe).
- **All commits must end with** `Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>` — match the existing commit style on this branch.
- Every task is designed so both iOS and macOS builds stay green after the task's final step. The refactor in Tasks 10–13 intentionally keeps old and new code paths coexisting until the last cleanup task flips the switch.

---

## Task 0: Preflight — confirm starting state

**Files:** None modified.

- [ ] **Step 1: Verify branch and clean working tree**

Run: `git status && git branch --show-current`
Expected: Working tree clean, branch `feature/dashboard-revamp`.

- [ ] **Step 2: Run the full existing test suite on macOS**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' -quiet 2>&1 | tail -30`
Expected: All existing tests pass (`DashboardViewModelTests`, `ExchangeManagerTests`, `KeychainServiceTests`, `ModelTests`).

- [ ] **Step 3: Verify XcodeGen can regenerate the project**

Run: `xcodegen --version && xcodegen generate`
Expected: Regeneration succeeds. `CryptoTrack.xcodeproj` is restored to a known-good state after any hidden drift.

---

## Task 1: Create `PortfolioRow` model

**Files:**
- Create: `CryptoTrack/ViewModels/PortfolioRow.swift`

- [ ] **Step 1: Write the file**

```swift
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
    /// Unrealized profit restricted to the subset of holdings with a known cost basis.
    let profit: Double
    /// Profit rate (%) over the known-basis subset. Zero when `knownCost == 0`.
    let profitRate: Double

    /// True when at least one contributing asset has a known cost basis.
    let hasCostBasis: Bool
    /// True when some contributing assets have cost basis and others don't — the UI
    /// should display an "일부 미제공" hint.
    let hasPartialCostBasis: Bool
    /// True when at least one contributing asset has a matching ticker.
    let hasTicker: Bool
}
```

- [ ] **Step 2: Regenerate the Xcode project and compile**

Run: `xcodegen generate && xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: Build succeeds. The new file is unused but should compile cleanly.

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/ViewModels/PortfolioRow.swift CryptoTrack.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(dashboard): add PortfolioRow display model

Flat display model for both aggregated and single-exchange rows.
Fields are pre-computed to support SwiftUI Table's KeyPathComparator.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `PortfolioAggregator.aggregate` — single-currency, all cost basis known

**Files:**
- Create: `CryptoTrack/Services/PortfolioAggregator.swift`
- Create: `CryptoTrackTests/PortfolioAggregatorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `CryptoTrackTests/PortfolioAggregatorTests.swift`:

```swift
import XCTest
@testable import CryptoTrack

final class PortfolioAggregatorTests: XCTestCase {

    // MARK: - Helpers

    private func asset(
        _ symbol: String,
        balance: Double,
        avgPrice: Double,
        exchange: Exchange
    ) -> Asset {
        Asset(
            id: "\(exchange.rawValue)-\(symbol)",
            symbol: symbol,
            balance: balance,
            averageBuyPrice: avgPrice,
            exchange: exchange,
            lastUpdated: Date()
        )
    }

    private func ticker(
        _ symbol: String,
        price: Double,
        exchange: Exchange
    ) -> Ticker {
        Ticker(
            id: "\(exchange.rawValue)-\(symbol)",
            symbol: symbol,
            currentPrice: price,
            changeRate24h: 0,
            volume24h: 0,
            exchange: exchange,
            timestamp: Date()
        )
    }

    // MARK: - aggregate()

    /// Upbit 0.5 BTC @55M + Bithumb 0.3 BTC @60M, both tickers @62M.
    /// Expected single KRW row with known-only weighted average =
    /// (0.5*55M + 0.3*60M) / 0.8 = 56.875M, value-weighted price = 62M.
    func testAggregateKRWAllCostBasisKnown() {
        let assets = [
            asset("BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit),
            asset("BTC", balance: 0.3, avgPrice: 60_000_000, exchange: .bithumb),
        ]
        let tickers = [
            ticker("BTC", price: 62_000_000, exchange: .upbit),
            ticker("BTC", price: 62_000_000, exchange: .bithumb),
        ]

        let rows = PortfolioAggregator.aggregate(assets: assets, tickers: tickers)
        XCTAssertEqual(rows.count, 1)

        let row = rows[0]
        XCTAssertEqual(row.symbol, "BTC")
        XCTAssertEqual(row.quoteCurrency, .krw)
        // Exchange.allCases order puts .upbit before .bithumb.
        XCTAssertEqual(row.exchanges, [.upbit, .bithumb])
        XCTAssertEqual(row.totalBalance, 0.8, accuracy: 1e-9)
        XCTAssertEqual(row.averageBuyPrice, 56_875_000, accuracy: 0.5)
        XCTAssertEqual(row.currentPrice, 62_000_000, accuracy: 0.5)
        XCTAssertEqual(row.currentValue, 49_600_000, accuracy: 0.5)
        XCTAssertEqual(row.profit, 4_100_000, accuracy: 0.5)
        XCTAssertEqual(row.profitRate, (4_100_000.0 / 45_500_000.0) * 100, accuracy: 0.01)
        XCTAssertTrue(row.hasCostBasis)
        XCTAssertFalse(row.hasPartialCostBasis)
        XCTAssertTrue(row.hasTicker)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/PortfolioAggregatorTests 2>&1 | tail -20`
Expected: FAIL with `PortfolioAggregator` unresolved identifier.

- [ ] **Step 3: Implement `PortfolioAggregator.aggregate`**

Create `CryptoTrack/Services/PortfolioAggregator.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/PortfolioAggregatorTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add CryptoTrack/Services/PortfolioAggregator.swift CryptoTrackTests/PortfolioAggregatorTests.swift CryptoTrack.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(dashboard): add PortfolioAggregator with KRW aggregation

Pure aggregation pipeline that groups assets by (symbol, quoteCurrency)
and folds balances/cost basis/ticker values into a PortfolioRow.
Covers the single-currency all-cost-basis-known case.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Aggregator — partial cost basis

**Files:**
- Modify: `CryptoTrackTests/PortfolioAggregatorTests.swift`

- [ ] **Step 1: Append the failing test**

Add this method inside `PortfolioAggregatorTests`:

```swift
/// Upbit 0.5 BTC @55M (known) + Bithumb 0.3 BTC @0 (unknown).
/// - averageBuyPrice = 55M (only Upbit's cost basis contributes)
/// - profit = known-only: 0.5 * 62M - 0.5 * 55M = 3.5M
/// - hasPartialCostBasis = true
func testAggregatePartialCostBasis() {
    let assets = [
        asset("BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit),
        asset("BTC", balance: 0.3, avgPrice: 0, exchange: .bithumb),
    ]
    let tickers = [
        ticker("BTC", price: 62_000_000, exchange: .upbit),
        ticker("BTC", price: 62_000_000, exchange: .bithumb),
    ]

    let rows = PortfolioAggregator.aggregate(assets: assets, tickers: tickers)
    XCTAssertEqual(rows.count, 1)

    let row = rows[0]
    XCTAssertEqual(row.totalBalance, 0.8, accuracy: 1e-9)
    XCTAssertEqual(row.averageBuyPrice, 55_000_000, accuracy: 0.5)
    XCTAssertEqual(row.currentValue, 49_600_000, accuracy: 0.5)
    XCTAssertEqual(row.profit, 3_500_000, accuracy: 0.5)
    XCTAssertTrue(row.hasCostBasis)
    XCTAssertTrue(row.hasPartialCostBasis)
}
```

- [ ] **Step 2: Run the test**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/PortfolioAggregatorTests/testAggregatePartialCostBasis 2>&1 | tail -15`
Expected: PASS on the first run — the aggregator already implements this behavior. If it fails, investigate before proceeding.

- [ ] **Step 3: Commit**

```bash
git add CryptoTrackTests/PortfolioAggregatorTests.swift
git commit -m "$(cat <<'EOF'
test(dashboard): cover partial cost basis in aggregator

Holdings without a cost basis are excluded from the weighted average
and profit. hasPartialCostBasis flags the row so the UI can warn.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Aggregator — no cost basis (foreign exchanges)

**Files:**
- Modify: `CryptoTrackTests/PortfolioAggregatorTests.swift`

- [ ] **Step 1: Append the test**

```swift
/// Binance 0.2 BTC + OKX 0.1 BTC, both avgBuyPrice 0 (foreign exchange APIs
/// typically don't return cost basis). Tickers at $47,500.
/// - hasCostBasis = false
/// - profit / profitRate = 0
func testAggregateForeignNoCostBasis() {
    let assets = [
        asset("BTC", balance: 0.2, avgPrice: 0, exchange: .binance),
        asset("BTC", balance: 0.1, avgPrice: 0, exchange: .okx),
    ]
    let tickers = [
        ticker("BTC", price: 47_500, exchange: .binance),
        ticker("BTC", price: 47_500, exchange: .okx),
    ]

    let rows = PortfolioAggregator.aggregate(assets: assets, tickers: tickers)
    XCTAssertEqual(rows.count, 1)

    let row = rows[0]
    XCTAssertEqual(row.quoteCurrency, .usdt)
    XCTAssertEqual(row.totalBalance, 0.3, accuracy: 1e-9)
    XCTAssertEqual(row.averageBuyPrice, 0)
    XCTAssertEqual(row.currentValue, 14_250, accuracy: 0.01)
    XCTAssertEqual(row.profit, 0)
    XCTAssertEqual(row.profitRate, 0)
    XCTAssertFalse(row.hasCostBasis)
    XCTAssertFalse(row.hasPartialCostBasis)
    // Exchange.allCases: binance < okx.
    XCTAssertEqual(row.exchanges, [.binance, .okx])
}
```

- [ ] **Step 2: Run and verify**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/PortfolioAggregatorTests/testAggregateForeignNoCostBasis 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add CryptoTrackTests/PortfolioAggregatorTests.swift
git commit -m "$(cat <<'EOF'
test(dashboard): cover foreign-exchange rows without cost basis

Binance and OKX don't expose avg buy price — the aggregated row should
report hasCostBasis == false and zero profit.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Aggregator — mixed currency never merges

**Files:**
- Modify: `CryptoTrackTests/PortfolioAggregatorTests.swift`

- [ ] **Step 1: Append the test**

```swift
/// Upbit 0.5 BTC (KRW) + Binance 0.2 BTC (USDT) must produce TWO rows —
/// one per quoteCurrency. They are never merged because we don't do FX.
func testAggregateMixedCurrencyStaysSeparate() {
    let assets = [
        asset("BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit),
        asset("BTC", balance: 0.2, avgPrice: 0, exchange: .binance),
    ]
    let tickers = [
        ticker("BTC", price: 62_000_000, exchange: .upbit),
        ticker("BTC", price: 47_500, exchange: .binance),
    ]

    let rows = PortfolioAggregator.aggregate(assets: assets, tickers: tickers)
    XCTAssertEqual(rows.count, 2)

    let krwRow = rows.first { $0.quoteCurrency == .krw }
    let usdRow = rows.first { $0.quoteCurrency == .usdt }
    XCTAssertNotNil(krwRow)
    XCTAssertNotNil(usdRow)
    XCTAssertEqual(krwRow?.totalBalance, 0.5, accuracy: 1e-9)
    XCTAssertEqual(krwRow?.exchanges, [.upbit])
    XCTAssertEqual(usdRow?.totalBalance, 0.2, accuracy: 1e-9)
    XCTAssertEqual(usdRow?.exchanges, [.binance])
}
```

- [ ] **Step 2: Run and verify**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/PortfolioAggregatorTests/testAggregateMixedCurrencyStaysSeparate 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add CryptoTrackTests/PortfolioAggregatorTests.swift
git commit -m "$(cat <<'EOF'
test(dashboard): assert same symbol in different currencies stays split

Upbit BTC (KRW) and Binance BTC (USDT) produce two rows — no FX
conversion is performed in the aggregator.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Aggregator — ticker missing on one holder

**Files:**
- Modify: `CryptoTrackTests/PortfolioAggregatorTests.swift`

- [ ] **Step 1: Append the test**

```swift
/// Upbit 0.5 BTC with ticker @62M + Bithumb 0.3 BTC with NO ticker.
/// - currentValue reflects only the holding whose ticker is known: 0.5 * 62M
/// - the row is still shown (hasTicker == true because at least one asset matched)
/// - currentPrice is value-weighted: 31M / 0.8 = 38.75M
func testAggregateTickerMissingOnOneHolder() {
    let assets = [
        asset("BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit),
        asset("BTC", balance: 0.3, avgPrice: 60_000_000, exchange: .bithumb),
    ]
    let tickers = [
        ticker("BTC", price: 62_000_000, exchange: .upbit),
        // no Bithumb ticker
    ]

    let rows = PortfolioAggregator.aggregate(assets: assets, tickers: tickers)
    XCTAssertEqual(rows.count, 1)

    let row = rows[0]
    XCTAssertEqual(row.currentValue, 31_000_000, accuracy: 0.5)
    XCTAssertEqual(row.currentPrice, 31_000_000 / 0.8, accuracy: 0.5)
    XCTAssertTrue(row.hasTicker)
}
```

- [ ] **Step 2: Run and verify**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/PortfolioAggregatorTests/testAggregateTickerMissingOnOneHolder 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add CryptoTrackTests/PortfolioAggregatorTests.swift
git commit -m "$(cat <<'EOF'
test(dashboard): cover partial ticker coverage across exchanges

Rows are still rendered when some contributing exchanges have no
ticker — missing tickers contribute 0 to value.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Aggregator — `singleExchangeRows`

**Files:**
- Modify: `CryptoTrack/Services/PortfolioAggregator.swift`
- Modify: `CryptoTrackTests/PortfolioAggregatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
/// When a specific exchange filter is selected we don't aggregate — each
/// Asset becomes its own row (a single exchange cannot hold the same symbol
/// twice). Exchanges array has exactly one element.
func testSingleExchangeRowsNoAggregation() {
    let assets = [
        asset("BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit),
        asset("ETH", balance: 3.2, avgPrice: 2_800_000, exchange: .upbit),
    ]
    let tickers = [
        ticker("BTC", price: 62_000_000, exchange: .upbit),
        ticker("ETH", price: 3_100_000, exchange: .upbit),
    ]

    let rows = PortfolioAggregator.singleExchangeRows(assets: assets, tickers: tickers)
    XCTAssertEqual(rows.count, 2)
    for row in rows {
        XCTAssertEqual(row.exchanges.count, 1)
        XCTAssertEqual(row.exchanges.first, .upbit)
        XCTAssertEqual(row.quoteCurrency, .krw)
        XCTAssertTrue(row.hasCostBasis)
    }
    let btc = rows.first { $0.symbol == "BTC" }!
    XCTAssertEqual(btc.id, "upbit-BTC")
    XCTAssertEqual(btc.currentValue, 31_000_000, accuracy: 0.5)
    XCTAssertEqual(btc.averageBuyPrice, 55_000_000, accuracy: 0.5)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/PortfolioAggregatorTests/testSingleExchangeRowsNoAggregation 2>&1 | tail -15`
Expected: FAIL — `singleExchangeRows` doesn't exist yet.

- [ ] **Step 3: Implement `singleExchangeRows`**

Add to `PortfolioAggregator`:

```swift
/// 1:1 conversion for the `.exchange(_)` filter. No grouping happens
/// (a single exchange cannot hold the same symbol twice), but the same
/// `PortfolioRow` shape is produced so the UI can consume one type.
static func singleExchangeRows(assets: [Asset], tickers: [Ticker]) -> [PortfolioRow] {
    let lookup = tickerLookup(tickers)
    return assets.map { asset in
        makeRow(
            id: "\(asset.exchange.rawValue.lowercased())-\(asset.symbol)",
            symbol: asset.symbol,
            quoteCurrency: asset.quoteCurrency,
            groupAssets: [asset],
            tickers: lookup
        )
    }
}
```

- [ ] **Step 4: Run all aggregator tests**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/PortfolioAggregatorTests 2>&1 | tail -20`
Expected: All 6 aggregator tests pass.

- [ ] **Step 5: Commit**

```bash
git add CryptoTrack/Services/PortfolioAggregator.swift CryptoTrackTests/PortfolioAggregatorTests.swift
git commit -m "$(cat <<'EOF'
feat(dashboard): add PortfolioAggregator.singleExchangeRows

1:1 conversion for the per-exchange filter that produces the same
PortfolioRow shape without grouping.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `ExchangeManager.fetchTickersPerExchange(symbolsByExchange:)` + caller

**Files:**
- Modify: `CryptoTrack/Services/ExchangeManager.swift`
- Modify: `CryptoTrack/ViewModels/DashboardViewModel.swift`

This is the **ticker-fetch bug fix**. After this task, the dashboard's missing-price symptom is resolved even though the UI rewrite hasn't happened yet.

- [ ] **Step 1: Replace the method signature in `ExchangeManager`**

Locate the existing `fetchTickersPerExchange(symbols:)` (around line 142 of `ExchangeManager.swift`) and replace the entire method with:

```swift
/// Per-exchange ticker fetch scoped to each exchange's own holdings. Each
/// exchange task only receives the symbols it was asked to fetch — previously
/// the callsite passed the union of all symbols, which caused single-batch
/// APIs (Binance/Upbit/Bithumb) to fail entire requests whenever any symbol
/// wasn't listed on that exchange.
func fetchTickersPerExchange(
    symbolsByExchange: [Exchange: [String]]
) async -> [(Exchange, Result<[Ticker], Error>)] {
    guard !registeredExchanges.isEmpty else { return [] }

    return await withTaskGroup(of: (Exchange, Result<[Ticker], Error>).self) { group in
        for exchange in registeredExchanges {
            guard let service = services[exchange] else { continue }
            let symbols = symbolsByExchange[exchange] ?? []
            group.addTask {
                guard !symbols.isEmpty else {
                    return (exchange, .success([]))
                }
                do {
                    let list = try await service.fetchTickers(symbols: symbols)
                    return (exchange, .success(list))
                } catch {
                    return (exchange, .failure(error))
                }
            }
        }

        var results: [(Exchange, Result<[Ticker], Error>)] = []
        for await item in group {
            results.append(item)
        }
        return results
    }
}
```

Delete the old `fetchTickersPerExchange(symbols:)` method entirely.

- [ ] **Step 2: Update `DashboardViewModel.refresh()`**

In `CryptoTrack/ViewModels/DashboardViewModel.swift`, locate `refresh()` and replace it with:

```swift
func refresh() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    let assetResults = await exchangeManager.fetchAssetsPerExchange()

    var newAssets: [Asset] = []
    var statuses: [ExchangeFetchStatus] = []
    for (exchange, result) in assetResults {
        switch result {
        case .success(let list):
            newAssets.append(contentsOf: list)
            statuses.append(.init(id: exchange, status: .success, lastError: nil))
        case .failure(let error):
            statuses.append(.init(id: exchange, status: .failed, lastError: error.localizedDescription))
        }
    }

    // Scope symbols per-exchange: each exchange only fetches tickers for
    // symbols it actually holds. Previously the callsite passed the union of
    // all symbols to every exchange, which caused batch ticker requests to
    // fail entirely when any symbol wasn't listed.
    let symbolsByExchange: [Exchange: [String]] = Dictionary(
        grouping: newAssets, by: \.exchange
    ).mapValues { Array(Set($0.map(\.symbol))) }

    let tickerResults = await exchangeManager.fetchTickersPerExchange(
        symbolsByExchange: symbolsByExchange
    )

    var newTickers: [Ticker] = []
    for (_, result) in tickerResults {
        if case .success(let list) = result {
            newTickers.append(contentsOf: list)
        }
    }

    self.assets = newAssets
    self.tickers = newTickers
    self.exchangeStatuses = statuses
    self.lastRefreshDate = Date()

    if newAssets.isEmpty && !statuses.isEmpty && statuses.allSatisfy({ $0.status == .failed }) {
        errorMessage = "모든 거래소에서 데이터를 불러오지 못했습니다."
    }
}
```

- [ ] **Step 3: Build both schemes and run the full test suite**

Run: `xcodegen generate && xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All existing tests pass. `ExchangeManagerTests` doesn't exercise `fetchTickersPerExchange`, so no regression is expected.

- [ ] **Step 4: Commit**

```bash
git add CryptoTrack/Services/ExchangeManager.swift CryptoTrack/ViewModels/DashboardViewModel.swift
git commit -m "$(cat <<'EOF'
fix(dashboard): scope ticker fetch per-exchange to stop cross-exchange failures

ExchangeManager.fetchTickersPerExchange now takes a per-exchange symbol
map. Each task only fetches tickers for symbols that exchange actually
holds, so holding a Binance-only coin no longer causes the Upbit batch
ticker request (or vice versa) to fail entirely.

Resolves the "current price shows '—' for all coins" regression caused
by the shared-symbol-union callsite.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Add `QuoteCurrency.sectionTitle`

**Files:**
- Modify: `CryptoTrack/Models/QuoteCurrency.swift`

- [ ] **Step 1: Add the computed property**

Append inside the existing `enum QuoteCurrency` block, after `displayName`:

```swift
    /// Dashboard section header label used when rendering aggregated rows.
    var sectionTitle: String {
        switch self {
        case .krw:  return "원화 거래소 (KRW)"
        case .usdt: return "해외 거래소 (USD)"
        }
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: Clean build.

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Models/QuoteCurrency.swift
git commit -m "$(cat <<'EOF'
feat(model): add QuoteCurrency.sectionTitle for dashboard section headers

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Additive `DashboardViewModel` — `displayedSections` alongside `displayedRows`

**Files:**
- Modify: `CryptoTrack/ViewModels/DashboardViewModel.swift`

This task is strictly **additive**: it introduces the new sectioned API alongside the existing flat `displayedRows` (which continues to feed the unchanged `AssetTable` / `AssetCardList`). Nothing is removed. Both platforms still build and all existing tests still pass.

- [ ] **Step 1: Add the `RowSection` type at the top of the file**

Add near the top of `DashboardViewModel.swift`, before the `@Observable` class:

```swift
/// A contiguous group of `PortfolioRow`s in the dashboard list, bounded by a
/// single `QuoteCurrency`. When the filter is `.all`, the view model emits
/// one section per currency present in the portfolio. When a single exchange
/// is selected, exactly one section is emitted (for that exchange's currency).
struct RowSection: Identifiable, Sendable {
    var id: QuoteCurrency
    var rows: [PortfolioRow]
}
```

- [ ] **Step 2: Add the new state and computed property inside the class**

In the "UI State" section, add the two new sort orders (do NOT remove the existing `tableSortOrder`):

```swift
/// Sort state for the KRW section in the new `AssetTableSections` view.
/// The default order mirrors the pre-refactor behaviour.
var krwSortOrder: [KeyPathComparator<PortfolioRow>] = [
    KeyPathComparator(\PortfolioRow.currentValue, order: .reverse)
]

/// Sort state for the USDT section in the new `AssetTableSections` view.
var usdSortOrder: [KeyPathComparator<PortfolioRow>] = [
    KeyPathComparator(\PortfolioRow.currentValue, order: .reverse)
]
```

In the "Display Rows" section, add a new computed property (do NOT touch the existing `displayedRows`):

```swift
/// Filtered + aggregated + dust-filtered rows, grouped by quoteCurrency and
/// sorted per section. Returns zero, one, or two sections depending on
/// which currencies are present under the current filter.
var displayedSections: [RowSection] {
    let filteredAssets = assets.filter { matchesFilter($0) }

    let rawRows: [PortfolioRow]
    switch selectedFilter {
    case .all:
        rawRows = PortfolioAggregator.aggregate(assets: filteredAssets, tickers: tickers)
    case .exchange:
        rawRows = PortfolioAggregator.singleExchangeRows(assets: filteredAssets, tickers: tickers)
    }

    let kept = rawRows.filter { !hideDust || !isDustRow($0) }

    let krwRows = kept
        .filter { $0.quoteCurrency == .krw }
        .sorted(using: krwSortOrder)
    let usdRows = kept
        .filter { $0.quoteCurrency == .usdt }
        .sorted(using: usdSortOrder)

    var sections: [RowSection] = []
    if !krwRows.isEmpty { sections.append(RowSection(id: .krw, rows: krwRows)) }
    if !usdRows.isEmpty { sections.append(RowSection(id: .usdt, rows: usdRows)) }
    return sections
}

/// Post-aggregation dust filter. A row is dust when its aggregated
/// `currentValue` is below the per-currency threshold AND at least one
/// contributing asset has a ticker (we can judge the value). Rows with no
/// ticker anywhere are never hidden.
private func isDustRow(_ row: PortfolioRow) -> Bool {
    guard row.hasTicker else { return false }
    let threshold: Double = row.quoteCurrency == .krw
        ? Self.dustThresholdKRW
        : Self.dustThresholdUSD
    return row.currentValue < threshold
}
```

- [ ] **Step 3: Build both schemes and run the full test suite**

Run: `xcodegen generate && xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' 2>&1 | tail -20`
Expected: Clean build. All existing `DashboardViewModelTests` pass (they still operate on the legacy `displayedRows`).

Run: `xcodebuild -scheme CryptoTrack_iOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`
Expected: Clean iOS build.

- [ ] **Step 4: Commit**

```bash
git add CryptoTrack/ViewModels/DashboardViewModel.swift
git commit -m "$(cat <<'EOF'
feat(dashboard): add displayedSections alongside displayedRows

Additive step: DashboardViewModel now exposes a sectioned view of
PortfolioRows suitable for the upcoming AssetTableSections renderer,
while the legacy displayedRows path remains untouched so current
views keep compiling and existing tests keep passing.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Rewrite `AssetCardList` (iOS) and wire it into `DashboardView`

**Files:**
- Modify: `CryptoTrack/Views/Dashboard/AssetCardList.swift`
- Modify: `CryptoTrack/Views/Dashboard/DashboardView.swift`

The old `AssetCardList(rows:)` is replaced with a sections-based version. The iOS branch of `DashboardView` is updated in the same commit so the iOS build stays green. macOS is not touched — it still uses the old `AssetTable(rows:)` path.

- [ ] **Step 1: Replace `AssetCardList.swift` entirely**

```swift
// CryptoTrack/Views/Dashboard/AssetCardList.swift
#if !os(macOS)
import SwiftUI

/// iOS-only section-aware card list. Renders one `Section` per
/// quoteCurrency with a header when `showSectionHeaders == true`
/// (i.e. the "전체" filter). When a specific exchange is selected we
/// pass `showSectionHeaders: false` so the list renders without header
/// decoration.
struct AssetCardList: View {
    let sections: [RowSection]
    let showSectionHeaders: Bool
    let colorMode: PriceColorMode

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        AssetCardRow(
                            row: row,
                            showBadges: showSectionHeaders,
                            colorMode: colorMode
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    if showSectionHeaders {
                        Text(section.id.sectionTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct AssetCardRow: View {
    let row: PortfolioRow
    let showBadges: Bool
    let colorMode: PriceColorMode

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(row.symbol)
                            .font(.headline)
                        // Badge slot — filled in Task 17.
                        if showBadges {
                            EmptyView()
                        }
                    }
                    Text("\(PriceFormatter.formatBalance(row.totalBalance)) \(row.symbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PriceFormatter.formatPrice(row.currentValue, currency: row.quoteCurrency))
                        .font(.headline)
                        .monospacedDigit()
                    if row.hasCostBasis {
                        Text(PriceFormatter.formatRate(row.profitRate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PriceColor.color(for: row.profitRate, mode: colorMode))
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack(spacing: 16) {
                infoPair(
                    label: "평단",
                    value: row.hasCostBasis
                        ? PriceFormatter.formatPrice(row.averageBuyPrice, currency: row.quoteCurrency)
                        : "—"
                )
                infoPair(
                    label: "현재가",
                    value: row.hasTicker
                        ? PriceFormatter.formatPrice(row.currentPrice, currency: row.quoteCurrency)
                        : "—"
                )
                if row.hasPartialCostBasis {
                    Text("일부 미제공")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background.secondary)
        )
    }

    private func infoPair(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}
#endif
```

- [ ] **Step 2: Update the iOS branch in `DashboardView.swift`**

Find the existing `assetsList` computed view and replace it with:

```swift
@ViewBuilder
private var assetsList: some View {
    #if os(macOS)
    // macOS path unchanged in this task — still uses the old AssetTable.
    if viewModel.displayedRows.isEmpty {
        emptyFilterView
    } else {
        AssetTable(
            rows: viewModel.displayedRows,
            sortOrder: $viewModel.tableSortOrder,
            colorMode: settingsManager.priceColorMode
        )
    }
    #else
    if viewModel.displayedSections.isEmpty {
        emptyFilterView
    } else {
        AssetCardList(
            sections: viewModel.displayedSections,
            showSectionHeaders: viewModel.selectedFilter == .all,
            colorMode: settingsManager.priceColorMode
        )
    }
    #endif
}
```

`hasOnlyDust` currently references `viewModel.displayedRows.isEmpty`. On iOS that is still reachable (AssetRow type still exists because Task 13 will delete it). Do NOT change `hasOnlyDust` in this task.

- [ ] **Step 3: Build both schemes and run tests**

Run: `xcodebuild -scheme CryptoTrack_iOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -10`
Expected: Clean iOS build using the new `AssetCardList`.

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' 2>&1 | tail -20`
Expected: Clean macOS build (AssetTable still uses the old path). All tests pass.

- [ ] **Step 4: Commit**

```bash
git add CryptoTrack/Views/Dashboard/AssetCardList.swift CryptoTrack/Views/Dashboard/DashboardView.swift
git commit -m "$(cat <<'EOF'
refactor(dashboard): rewrite iOS AssetCardList around RowSection

List rendering now uses Section per quoteCurrency and hides headers
when a specific exchange is filtered. macOS still uses the legacy
AssetTable(rows:) path — migrated in the next task.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Replace `AssetTable` with `AssetTableSections` and wire the macOS branch

**Files:**
- Modify: `CryptoTrack/Views/Dashboard/AssetTable.swift`
- Modify: `CryptoTrack/Views/Dashboard/DashboardView.swift`

- [ ] **Step 1: Replace `AssetTable.swift` entirely**

```swift
// CryptoTrack/Views/Dashboard/AssetTable.swift
#if os(macOS)
import SwiftUI

/// macOS-only section-aware table renderer.
///
/// SwiftUI `Table` does not support sections natively, so we stack two
/// `Table`s vertically when showing both KRW and USD groups. Each section
/// owns its own `KeyPathComparator` binding so column-click sorting is
/// independent per section. When only one section is present (i.e. the
/// `.exchange` filter is selected), we render a single `Table`.
struct AssetTableSections: View {
    let sections: [RowSection]
    @Binding var krwSortOrder: [KeyPathComparator<PortfolioRow>]
    @Binding var usdSortOrder: [KeyPathComparator<PortfolioRow>]
    let showHeaders: Bool
    let colorMode: PriceColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if showHeaders {
                        Text(section.id.sectionTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    sectionTable(for: section)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionTable(for section: RowSection) -> some View {
        switch section.id {
        case .krw:
            table(rows: section.rows, sortOrder: $krwSortOrder)
        case .usdt:
            table(rows: section.rows, sortOrder: $usdSortOrder)
        }
    }

    private func table(
        rows: [PortfolioRow],
        sortOrder: Binding<[KeyPathComparator<PortfolioRow>]>
    ) -> some View {
        Table(rows, sortOrder: sortOrder) {
            TableColumn("코인") { row in
                HStack(spacing: 8) {
                    Text(row.symbol).font(.body.weight(.semibold))
                    // Badge slot — filled in Task 17.
                    if showHeaders {
                        EmptyView()
                    }
                }
            }
            .width(min: 120, ideal: 180)

            TableColumn("보유량", value: \.totalBalance) { row in
                Text(PriceFormatter.formatBalance(row.totalBalance))
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn("평단가", value: \.averageBuyPrice) { row in
                if row.hasCostBasis {
                    HStack(spacing: 4) {
                        Text(PriceFormatter.formatPrice(row.averageBuyPrice, currency: row.quoteCurrency))
                            .monospacedDigit()
                        if row.hasPartialCostBasis {
                            Text("일부")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 140)

            TableColumn("현재가", value: \.currentPrice) { row in
                if row.hasTicker {
                    Text(PriceFormatter.formatPrice(row.currentPrice, currency: row.quoteCurrency))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 140)

            TableColumn("평가금액", value: \.currentValue) { row in
                Text(PriceFormatter.formatPrice(row.currentValue, currency: row.quoteCurrency))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .width(min: 110, ideal: 150)

            TableColumn("수익률", value: \.profitRate) { row in
                if row.hasCostBasis {
                    Text(PriceFormatter.formatRate(row.profitRate))
                        .foregroundStyle(PriceColor.color(for: row.profitRate, mode: colorMode))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)
        }
    }
}
#endif
```

Note: the old `AssetTable` struct is deleted. This breaks the macOS branch of `DashboardView` until Step 2.

- [ ] **Step 2: Update the macOS branch in `DashboardView.swift`**

Replace `assetsList` with the symmetric version that wires both platforms to the new API:

```swift
@ViewBuilder
private var assetsList: some View {
    if viewModel.displayedSections.isEmpty {
        emptyFilterView
    } else {
        #if os(macOS)
        AssetTableSections(
            sections: viewModel.displayedSections,
            krwSortOrder: $viewModel.krwSortOrder,
            usdSortOrder: $viewModel.usdSortOrder,
            showHeaders: viewModel.selectedFilter == .all,
            colorMode: settingsManager.priceColorMode
        )
        .padding(.horizontal, 16)
        #else
        AssetCardList(
            sections: viewModel.displayedSections,
            showSectionHeaders: viewModel.selectedFilter == .all,
            colorMode: settingsManager.priceColorMode
        )
        #endif
    }
}
```

`hasOnlyDust` currently references `viewModel.displayedRows.isEmpty`. Update it to use the sectioned API:

```swift
/// Dust-only short-circuit: some rows were filtered, but flipping the dust
/// toggle would bring them back.
private var hasOnlyDust: Bool {
    let unfilteredCount = viewModel.assets.filter { asset in
        switch viewModel.selectedFilter {
        case .all: return true
        case .exchange(let ex): return asset.exchange == ex
        }
    }.count
    return unfilteredCount > 0 && viewModel.displayedSections.allSatisfy(\.rows.isEmpty)
}
```

- [ ] **Step 3: Build both schemes**

Run: `xcodegen generate && xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: Clean macOS build using the new `AssetTableSections`.

Run: `xcodebuild -scheme CryptoTrack_iOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -10`
Expected: Clean iOS build.

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests pass. Note: the ViewModel still exposes the legacy `displayedRows: [AssetRow]` property (used by tests) — it will be removed in Task 13.

- [ ] **Step 5: Commit**

```bash
git add CryptoTrack/Views/Dashboard/AssetTable.swift CryptoTrack/Views/Dashboard/DashboardView.swift
git commit -m "$(cat <<'EOF'
refactor(dashboard): replace AssetTable with AssetTableSections

Two stacked SwiftUI Tables (one per section) for macOS, wired through
DashboardView alongside the already-migrated iOS path. Both platforms
now consume displayedSections; legacy displayedRows becomes dead weight
on the view side and will be removed in the next task.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Cleanup — remove `AssetRow`, legacy ViewModel state, and update tests

**Files:**
- Delete: `CryptoTrack/ViewModels/AssetRow.swift`
- Modify: `CryptoTrack/ViewModels/DashboardViewModel.swift`
- Modify: `CryptoTrackTests/DashboardViewModelTests.swift`

- [ ] **Step 1: Remove legacy state and add a compatibility shim to the ViewModel**

Open `CryptoTrack/ViewModels/DashboardViewModel.swift` and remove:

- The `tableSortOrder: [KeyPathComparator<AssetRow>]` property (including its default value and comment).
- The old `displayedRows: [AssetRow]` computed property that used `makeRow(for:)`.
- The `private func makeRow(for asset: Asset) -> AssetRow` helper.
- The old `private func isDust(_ row: AssetRow) -> Bool` helper (the new `isDustRow(_:)` added in Task 10 replaces it).

Immediately after `displayedSections`, add this compatibility shim so the existing tests keep compiling without a wholesale rewrite:

```swift
/// Flat view of all rows across all sections. Preserved so that existing
/// `DashboardViewModelTests` cases can assert on row counts and ordering
/// without having to walk section by section.
var displayedRows: [PortfolioRow] {
    displayedSections.flatMap(\.rows)
}
```

Keep the existing `ticker(for:)` and `currentValue(for:)` helpers — they're still referenced by `DashboardViewModelTests` and their semantics already match the aggregator's exact-match rule.

- [ ] **Step 2: Delete `AssetRow.swift`**

```bash
git rm CryptoTrack/ViewModels/AssetRow.swift
```

- [ ] **Step 3: Update the single test line that references the old `.exchange` field**

In `CryptoTrackTests/DashboardViewModelTests.swift`, find the assertion inside `testFilterByExchangeReturnsOnlyThatExchange`:

```swift
        XCTAssertEqual(viewModel.displayedRows.first?.exchange, .upbit)
```

Replace it with:

```swift
        XCTAssertEqual(viewModel.displayedRows.first?.exchanges, [.upbit])
```

No other test line needs to change — `PortfolioRow` exposes `symbol`, `currentValue`, and count semantics identical to the old `AssetRow`.

- [ ] **Step 4: Regenerate and run the full test suite on both platforms**

Run: `xcodegen generate && xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass. Every `PortfolioAggregatorTests` case (7 total including `singleExchangeRows`) and every `DashboardViewModelTests` case.

Run: `xcodebuild test -scheme CryptoTrack_iOS -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -20`
Expected: Same suite passes on iOS.

- [ ] **Step 5: Commit**

```bash
git add CryptoTrack/ViewModels/DashboardViewModel.swift CryptoTrackTests/DashboardViewModelTests.swift CryptoTrack.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
refactor(dashboard): delete AssetRow, rebase displayedRows on sections

Removes the legacy flat AssetRow plumbing now that both platforms
consume displayedSections. displayedRows survives as a flatMap shim so
the ViewModel tests keep working, and the one .exchange field
reference is updated to the new .exchanges plural.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Manual smoke check before branding work

**Files:** None — visual sanity check.

- [ ] **Step 1: Launch the macOS app**

Open `CryptoTrack.xcodeproj` in Xcode and press Run on the `CryptoTrack_macOS` scheme, or run:

```bash
xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' -configuration Debug build 2>&1 | tail -3
```

and launch the resulting `.app` bundle manually.

- [ ] **Step 2: Verify the three golden-path scenarios**

Confirm visually:

1. **Single KRW exchange (Upbit)** registered → "전체" tab shows one section `원화 거래소 (KRW)` with Upbit assets, each row has the correct current price and profit. Selecting the Upbit tab hides the section header.
2. **Mixed (Upbit + Binance)** registered → "전체" shows two sections. Both sections have populated `현재가` columns. **This is the bug-fix verification — current prices must NOT be "—".**
3. **Same coin on two KRW exchanges** (BTC on Upbit + Bithumb, if you have keys) → "전체" shows a single BTC row with summed balance and weighted average price.

- [ ] **Step 3: Fix any issues before branding work**

If any of the three scenarios misbehaves, stop and root-cause. Do NOT proceed to branding work on a broken data layer.

No commit for this task — it's a checkpoint.

---

## Task 15: `Exchange+Brand` extension

**Files:**
- Create: `CryptoTrack/DesignSystem/Exchange+Brand.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Presentation-layer brand metadata for each exchange.
///
/// Used by `ExchangeBadge` to render either a bundled logo asset or a
/// brand-colored monogram circle fallback. Swapping logos for monograms
/// is a kill-switch: delete the imageset from
/// `Assets.xcassets/Logo/` and the badge automatically reverts to the
/// monogram path without any code changes.
extension Exchange {

    /// Representative brand color. Used as the monogram circle background
    /// and as a general accent for exchange-themed UI.
    var brandColor: Color {
        switch self {
        case .upbit:   return Color(red: 0.00, green: 0.40, blue: 0.94)
        case .binance: return Color(red: 0.94, green: 0.73, blue: 0.00)
        case .bithumb: return Color(red: 0.95, green: 0.38, blue: 0.00)
        case .bybit:   return Color(red: 0.95, green: 0.75, blue: 0.14)
        case .coinone: return Color(red: 0.09, green: 0.21, blue: 0.52)
        case .korbit:  return Color(red: 0.00, green: 0.55, blue: 0.85)
        case .okx:     return Color.black
        }
    }

    /// 1–2 character abbreviation used in the monogram fallback.
    var monogram: String {
        switch self {
        case .upbit:   return "U"
        case .binance: return "B"
        case .bithumb: return "Bt"
        case .bybit:   return "By"
        case .coinone: return "Co"
        case .korbit:  return "K"
        case .okx:     return "OK"
        }
    }

    /// Name of the bundled image asset for this exchange's logo. The name
    /// is resolved against `Logo/` inside `Assets.xcassets`, which uses
    /// `provides-namespace: true`, so the full asset name is
    /// `"Logo/<exchange>"`. If the asset is missing, `ExchangeBadge`
    /// falls back to the monogram circle.
    var logoAssetName: String { "Logo/\(rawValue.lowercased())" }
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: Clean build.

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/DesignSystem/Exchange+Brand.swift CryptoTrack.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(dashboard): add Exchange+Brand presentation metadata

brandColor / monogram / logoAssetName — foundation for ExchangeBadge.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: `ExchangeBadge` + `ExchangeBadgeRow` components

**Files:**
- Create: `CryptoTrack/Views/Dashboard/Components/ExchangeBadge.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

#if canImport(UIKit)
import UIKit
private func loadPlatformImage(named name: String) -> UIImage? { UIImage(named: name) }
#elseif canImport(AppKit)
import AppKit
private func loadPlatformImage(named name: String) -> NSImage? { NSImage(named: name) }
#endif

/// Circular badge identifying a single exchange.
///
/// Rendering strategy:
/// 1. If the bundled image asset named `exchange.logoAssetName` exists,
///    display the image clipped to a circle.
/// 2. Otherwise fall back to a brand-colored circle with the exchange's
///    monogram in white.
///
/// This hybrid is the kill-switch contract: deleting a logo asset
/// automatically reverts to the monogram without any code changes.
struct ExchangeBadge: View {
    let exchange: Exchange
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            if loadPlatformImage(named: exchange.logoAssetName) != nil {
                Image(exchange.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(exchange.brandColor)
                    .frame(width: size, height: size)
                Text(exchange.monogram)
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(exchange.rawValue))
    }
}

/// Horizontal strip of `ExchangeBadge`s, ordered by `Exchange.allCases`
/// for stable rendering. When more than `maxVisible` exchanges are
/// present, the remainder is collapsed to a `+N` indicator.
struct ExchangeBadgeRow: View {
    let exchanges: [Exchange]
    var size: CGFloat = 16
    var maxVisible: Int = 4

    var body: some View {
        let sorted = Exchange.allCases.filter { exchanges.contains($0) }
        let visible = sorted.prefix(maxVisible)
        let overflow = max(sorted.count - maxVisible, 0)

        HStack(spacing: -4) {
            ForEach(Array(visible), id: \.self) { exchange in
                ExchangeBadge(exchange: exchange, size: size)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5)
                    )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
        }
    }
}

#Preview("ExchangeBadge — all exchanges") {
    HStack(spacing: 12) {
        ForEach(Exchange.allCases, id: \.self) { ex in
            ExchangeBadge(exchange: ex, size: 28)
        }
    }
    .padding()
}

#Preview("ExchangeBadgeRow — overflow") {
    VStack(alignment: .leading, spacing: 12) {
        ExchangeBadgeRow(exchanges: [.upbit, .bithumb], size: 16)
        ExchangeBadgeRow(exchanges: [.upbit, .bithumb, .coinone, .korbit], size: 16)
        ExchangeBadgeRow(exchanges: [.upbit, .bithumb, .coinone, .korbit, .binance, .okx], size: 16)
    }
    .padding()
}
```

- [ ] **Step 2: Build both schemes**

Run: `xcodegen generate && xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5 && xcodebuild -scheme CryptoTrack_iOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`
Expected: Both clean.

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Views/Dashboard/Components/ExchangeBadge.swift CryptoTrack.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(dashboard): add ExchangeBadge + ExchangeBadgeRow

Circular badge that prefers a bundled logo asset and falls back to a
brand-colored monogram when the asset is missing. Row variant stacks
multiple badges with an overflow counter.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 17: Integrate `ExchangeBadgeRow` into both list views

**Files:**
- Modify: `CryptoTrack/Views/Dashboard/AssetCardList.swift`
- Modify: `CryptoTrack/Views/Dashboard/AssetTable.swift`

- [ ] **Step 1: Replace the badge slot in `AssetCardList.swift`**

Find:
```swift
                        if showBadges {
                            EmptyView()
                        }
```

Replace with:
```swift
                        if showBadges {
                            ExchangeBadgeRow(exchanges: row.exchanges, size: 16)
                        }
```

- [ ] **Step 2: Replace the badge slot in `AssetTable.swift`**

Find:
```swift
                    if showHeaders {
                        EmptyView()
                    }
```

Replace with:
```swift
                    if showHeaders {
                        ExchangeBadgeRow(exchanges: row.exchanges, size: 14)
                    }
```

- [ ] **Step 3: Build both schemes**

Run: `xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5 && xcodebuild -scheme CryptoTrack_iOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`
Expected: Both clean.

- [ ] **Step 4: Visual check**

Launch macOS target. In the "전체" tab with two exchanges registered, verify the badge row is visible next to each coin symbol. Rows in a specific-exchange filter should NOT show badges. Since no logo assets exist yet, all badges render as brand-colored monogram circles — this is the expected state.

- [ ] **Step 5: Commit**

```bash
git add CryptoTrack/Views/Dashboard/AssetCardList.swift CryptoTrack/Views/Dashboard/AssetTable.swift
git commit -m "$(cat <<'EOF'
feat(dashboard): show ExchangeBadgeRow next to aggregated coin symbols

Badges appear only when the 전체 filter is active; specific-exchange
filters suppress the badge strip because it would be redundant.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 18: Create `Assets.xcassets` catalog skeleton

**Files:**
- Create: `CryptoTrack/Assets.xcassets/Contents.json`
- Create: `CryptoTrack/Assets.xcassets/Logo/Contents.json`

- [ ] **Step 1: Create the catalog directories**

```bash
mkdir -p CryptoTrack/Assets.xcassets/Logo
```

- [ ] **Step 2: Write the catalog root `Contents.json`**

Create `CryptoTrack/Assets.xcassets/Contents.json` with:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Write the `Logo/` group `Contents.json`**

Create `CryptoTrack/Assets.xcassets/Logo/Contents.json` with:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "provides-namespace" : true
  }
}
```

`provides-namespace: true` means the imagesets inside `Logo/` are addressed as `"Logo/<name>"` — matching `Exchange.logoAssetName`.

- [ ] **Step 4: Regenerate and build**

Run: `xcodegen generate && xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: Clean build. Badges continue to render via the monogram fallback because no imagesets exist yet.

- [ ] **Step 5: Commit**

```bash
git add CryptoTrack/Assets.xcassets/ CryptoTrack.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
chore(assets): add empty Logo namespace to Assets.xcassets

Empty catalog so ExchangeBadge continues to render monogram fallback.
Actual logo files are added in the next task.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 19: Download exchange logos

**Files:**
- Create: `CryptoTrack/Assets.xcassets/Logo/upbit.imageset/Contents.json` + image file
- Create: `CryptoTrack/Assets.xcassets/Logo/binance.imageset/Contents.json` + image file
- Create: `CryptoTrack/Assets.xcassets/Logo/bithumb.imageset/Contents.json` + image file
- Create: `CryptoTrack/Assets.xcassets/Logo/bybit.imageset/Contents.json` + image file
- Create: `CryptoTrack/Assets.xcassets/Logo/coinone.imageset/Contents.json` + image file
- Create: `CryptoTrack/Assets.xcassets/Logo/korbit.imageset/Contents.json` + image file
- Create: `CryptoTrack/Assets.xcassets/Logo/okx.imageset/Contents.json` + image file

This task intentionally has per-exchange subtasks instead of one bulk step because network fetches are fallible — each exchange commits independently so partial success leaves the repo in a clean state. If any exchange's download fails or the result is visually wrong, skip its imageset entirely and the monogram fallback kicks in automatically.

### Common subtask pattern

For each exchange in `[upbit, binance, bithumb, bybit, coinone, korbit, okx]`:

- [ ] **Step 1: Find a candidate logo URL**

Use the `WebSearch` tool with query `"<ExchangeName> logo svg wikimedia commons"`. The goal is to locate either:
  - A Wikimedia Commons `File:` page URL (preferred — stable CDN), or
  - The exchange's official brand-kit page URL.

For the Wikimedia path: navigate to the `File:` page, extract the direct SVG URL from the "Original file" link (typically `https://upload.wikimedia.org/wikipedia/commons/...`).

- [ ] **Step 2: Download the file**

```bash
curl -fsSL --output "/tmp/<exchange>.svg" "<URL>"
file "/tmp/<exchange>.svg"
ls -l "/tmp/<exchange>.svg"
```

Verify:
- `curl` exit code 0.
- `file` reports "SVG", "XML", or similar vector format.
- File size ≥ 200 bytes (smaller is usually a 404 placeholder).

If validation fails, try the second-priority source (brand kit). If both sources fail for this exchange, **skip it** — move to the next exchange. The monogram fallback handles it.

- [ ] **Step 3: Inspect the SVG for suitability**

Open the SVG file and verify:
- It contains actual logo geometry, not a "File not found" placeholder.
- It uses a sensible `viewBox` so it'll scale cleanly to a 14–16pt circular crop.
- It isn't a text-only "word mark" that'll be illegible at small sizes — those are poor candidates; prefer icon-style logos.

If the SVG looks wrong, search for an alternative source or skip this exchange and move on.

- [ ] **Step 4: Create the imageset and move the file**

```bash
mkdir -p "CryptoTrack/Assets.xcassets/Logo/<exchange>.imageset"
mv "/tmp/<exchange>.svg" "CryptoTrack/Assets.xcassets/Logo/<exchange>.imageset/<exchange>.svg"
```

Write `CryptoTrack/Assets.xcassets/Logo/<exchange>.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "<exchange>.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true
  }
}
```

- [ ] **Step 5: Build and verify the logo appears**

Run: `xcodegen generate && xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: Clean build.

Launch the app and confirm the new logo appears in place of the monogram for this exchange. If the result looks wrong (clipped, off-center, wrong colors, unreadable at small sizes), either re-source the file or `git rm` the imageset to revert to the monogram for that exchange.

- [ ] **Step 6: Commit the single exchange**

```bash
git add "CryptoTrack/Assets.xcassets/Logo/<exchange>.imageset/" CryptoTrack.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
assets(logo): add <ExchangeName> logo from <source-domain>

Source: <exact URL used>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Running all seven exchanges

Repeat the above 6-step pattern sequentially for each of the 7 exchanges. Each exchange is independently committed, so you can stop partway and still ship a working build. At the end some exchanges may have real logos while others still render as monograms — both states are acceptable.

---

## Task 20: README trademark note

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append the trademark disclosure**

Open `README.md` and append at the end (or under an existing `## Credits` / `## Acknowledgments` section if one exists):

```markdown
## Third-Party Trademarks

Exchange logos displayed in this app (Upbit, Binance, Bithumb, Bybit,
Coinone, Korbit, OKX) are trademarks of their respective owners and are
used solely for nominative identification — to help users see which
exchange a given asset resides in. No affiliation with or endorsement
by any listed exchange is implied.

Logos can be removed at any time by deleting the corresponding imageset
under `CryptoTrack/Assets.xcassets/Logo/`. The UI automatically falls
back to a brand-colored monogram circle in that case.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs: add nominative-fair-use trademark note for exchange logos

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 21: Final verification

**Files:** None.

- [ ] **Step 1: Run the full test suite on macOS**

Run: `xcodebuild test -scheme CryptoTrack_macOS -destination 'platform=macOS' 2>&1 | tail -40`
Expected: All tests pass. Watch for:
- 7 `PortfolioAggregatorTests` cases green
- `DashboardViewModelTests` all green (including the updated `.exchanges` plural assertion)
- `ExchangeManagerTests`, `KeychainServiceTests`, `ModelTests` all green

- [ ] **Step 2: Run the full test suite on iOS Simulator**

Run: `xcodebuild test -scheme CryptoTrack_iOS -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -20`
Expected: Same suite passes on iOS.

- [ ] **Step 3: Launch macOS app and walk through the manual scenarios**

1. **Empty state** (no exchanges registered) → empty-state view with "설정 탭에서 거래소 API를 등록하면..." message.
2. **Single Upbit** registered → "전체" shows one KRW section, Upbit tab shows the same rows without the section header. No badges on the Upbit tab. In the "전체" tab, single-exchange rows still show a 1-badge strip (Upbit only).
3. **Upbit + Binance** registered → "전체" shows two sections (KRW + USD). Both sections have populated `현재가` — this is the ticker-scoping bug-fix verification. Selecting the Binance tab shows only the USD section without a header. Selecting Upbit shows only KRW.
4. **Duplicate coin** (BTC on Upbit + Bithumb, if possible) → "전체" shows one BTC row in the KRW section with summed balance and 2 badges. Bithumb tab shows only Bithumb BTC. Upbit tab shows only Upbit BTC.
5. **Dust toggle** → toggling "소액 숨김" shows/hides small-value rows. The empty filter view should offer the "소액 숨김 해제" button when all rows are dust.
6. **Column sort (macOS)** → clicking column headers in the KRW table sorts that section only; USD section stays put. Same for USD table.
7. **Refresh** → manually refresh; prices update; `lastRefreshDate` updates.

- [ ] **Step 4: Walk the same scenarios on iOS simulator**

Skip the column-sort scenario (iOS uses the default order). Everything else should match.

- [ ] **Step 5: Decide on merge path**

Invoke the `superpowers:finishing-a-development-branch` skill to choose how to land `feature/dashboard-revamp` onto `develop` (PR vs direct merge). Follow its workflow from there.

---

## Self-review notes (from author)

- Each task in the 10–13 refactor block keeps both platforms building on the
  task's final step. Task 10 is purely additive; Tasks 11 & 12 migrate one
  platform at a time; Task 13 is the cleanup sweep.
- `PortfolioRow.id` uses lowercase exchange raw-value so row IDs match the
  `Asset.id` format (e.g. `"upbit-BTC"`).
- `displayedRows` is preserved after Task 13 as a `flatMap(\.rows)` compat
  shim purely for the existing test file. The only test line change is the
  `.exchange` → `.exchanges` field access.
- `logoAssetName` returns `"Logo/<exchange>"` to match `provides-namespace:
  true` on the catalog's `Logo/` group. Using a plain `"logo.<exchange>"`
  name with a flat catalog is also valid but diverges from the Xcode
  convention of namespaced image groups.
- Sort state lives on the ViewModel without `#if os(macOS)` wrapping. iOS
  simply ignores the bindings — cleaner than splitting the API.
- The plan assumes XcodeGen is installed and on PATH. If `xcodegen generate`
  fails at any step, stop and re-evaluate — there is no manual
  `project.pbxproj` edit path planned.
