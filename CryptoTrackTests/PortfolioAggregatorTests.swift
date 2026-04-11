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
