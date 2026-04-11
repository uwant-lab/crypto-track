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
        exchange: Exchange,
        changeRate: Double = 0
    ) -> Ticker {
        Ticker(
            id: "\(exchange.rawValue)-\(symbol)",
            symbol: symbol,
            currentPrice: price,
            changeRate24h: changeRate,
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
        XCTAssertEqual(krwRow!.totalBalance, 0.5, accuracy: 1e-9)
        XCTAssertEqual(krwRow?.exchanges, [.upbit])
        XCTAssertEqual(usdRow!.totalBalance, 0.2, accuracy: 1e-9)
        XCTAssertEqual(usdRow?.exchanges, [.binance])
    }

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

    // MARK: - totalCost / changeRate24h

    /// totalCost == Σ(balance × averageBuyPrice) limited to the known-cost subset.
    /// partial holdings: upbit known (0.5 @ 55M = 27.5M), bithumb unknown (contributes 0).
    func testAggregateTotalCostKnownOnly() {
        let assets = [
            asset("BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit),
            asset("BTC", balance: 0.3, avgPrice: 0,          exchange: .bithumb),
        ]
        let tickers = [
            ticker("BTC", price: 62_000_000, exchange: .upbit),
            ticker("BTC", price: 62_000_000, exchange: .bithumb),
        ]

        let rows = PortfolioAggregator.aggregate(assets: assets, tickers: tickers)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.totalCost, 27_500_000, accuracy: 0.5)
        XCTAssertTrue(row.hasPartialCostBasis)
        // Sanity: known-only subset profit matches value-cost.
        XCTAssertEqual(row.profit, 31_000_000 - 27_500_000, accuracy: 0.5)
    }

    /// Value-weighted 24h change: Upbit 0.5 BTC × 62M = 31M weight, Bithumb 0.3 BTC
    /// × 62M = 18.6M weight. rate = (5 * 31 + 10 * 18.6) / 49.6 ≈ 6.875%.
    /// Note: the weighting is by currentValue, not by balance — verify by using
    /// identical tickers so the check isolates the weighting calculation.
    func testChangeRate24hIsValueWeighted() {
        let assets = [
            asset("BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit),
            asset("BTC", balance: 0.3, avgPrice: 60_000_000, exchange: .bithumb),
        ]
        let tickers = [
            ticker("BTC", price: 62_000_000, exchange: .upbit,   changeRate: 5),
            ticker("BTC", price: 62_000_000, exchange: .bithumb, changeRate: 10),
        ]

        let rows = PortfolioAggregator.aggregate(assets: assets, tickers: tickers)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]

        let expected = (5.0 * 31_000_000 + 10.0 * 18_600_000) / 49_600_000
        XCTAssertNotNil(row.changeRate24h)
        XCTAssertEqual(row.changeRate24h ?? 0, expected, accuracy: 1e-6)
    }

    /// changeRate24h == nil when no contributing asset has a matching ticker.
    func testChangeRate24hNilWhenNoTickers() {
        let assets = [
            asset("BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit),
        ]
        let rows = PortfolioAggregator.aggregate(assets: assets, tickers: [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].changeRate24h)
    }
}
