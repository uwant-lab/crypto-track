import XCTest
@testable import CryptoTrack

final class ModelTests: XCTestCase {

    // MARK: - Asset Tests

    func testAssetTotalCost() {
        let asset = Asset(
            id: "upbit-BTC",
            symbol: "BTC",
            balance: 0.5,
            averageBuyPrice: 60_000_000,
            exchange: .upbit,
            lastUpdated: Date()
        )

        XCTAssertEqual(asset.totalCost, 30_000_000, accuracy: 0.001)
    }

    func testAssetTotalCostWithZeroBalance() {
        let asset = Asset(
            id: "upbit-ETH",
            symbol: "ETH",
            balance: 0.0,
            averageBuyPrice: 3_000_000,
            exchange: .upbit,
            lastUpdated: Date()
        )

        XCTAssertEqual(asset.totalCost, 0.0, accuracy: 0.001)
    }

    func testAssetTotalCostWithZeroPrice() {
        let asset = Asset(
            id: "binance-XRP",
            symbol: "XRP",
            balance: 1000.0,
            averageBuyPrice: 0.0,
            exchange: .binance,
            lastUpdated: Date()
        )

        XCTAssertEqual(asset.totalCost, 0.0, accuracy: 0.001)
    }

    func testAssetIdentifiable() {
        let id = "upbit-BTC-\(UUID().uuidString)"
        let asset = Asset(
            id: id,
            symbol: "BTC",
            balance: 1.0,
            averageBuyPrice: 50_000_000,
            exchange: .upbit,
            lastUpdated: Date()
        )

        XCTAssertEqual(asset.id, id)
    }

    func testAssetIdentifiableIsUnique() {
        let asset1 = Asset(
            id: "id-1",
            symbol: "BTC",
            balance: 1.0,
            averageBuyPrice: 50_000_000,
            exchange: .upbit,
            lastUpdated: Date()
        )
        let asset2 = Asset(
            id: "id-2",
            symbol: "BTC",
            balance: 1.0,
            averageBuyPrice: 50_000_000,
            exchange: .upbit,
            lastUpdated: Date()
        )

        XCTAssertNotEqual(asset1.id, asset2.id)
    }

    // MARK: - Ticker Tests

    func testTickerProperties() {
        let now = Date()
        let ticker = Ticker(
            id: "upbit-BTC",
            symbol: "BTC",
            currentPrice: 65_000_000,
            changeRate24h: 2.5,
            volume24h: 1234.567,
            exchange: .upbit,
            timestamp: now
        )

        XCTAssertEqual(ticker.id, "upbit-BTC")
        XCTAssertEqual(ticker.symbol, "BTC")
        XCTAssertEqual(ticker.currentPrice, 65_000_000, accuracy: 0.001)
        XCTAssertEqual(ticker.changeRate24h, 2.5, accuracy: 0.001)
        XCTAssertEqual(ticker.volume24h, 1234.567, accuracy: 0.001)
        XCTAssertEqual(ticker.exchange, .upbit)
        XCTAssertEqual(ticker.timestamp, now)
    }

    func testTickerNegativeChangeRate() {
        let ticker = Ticker(
            id: "binance-ETH",
            symbol: "ETH",
            currentPrice: 3_000,
            changeRate24h: -3.14,
            volume24h: 500_000,
            exchange: .binance,
            timestamp: Date()
        )

        XCTAssertEqual(ticker.changeRate24h, -3.14, accuracy: 0.001)
    }

    // MARK: - Exchange Enum Tests

    func testExchangeRawValues() {
        XCTAssertEqual(Exchange.upbit.rawValue, "Upbit")
        XCTAssertEqual(Exchange.binance.rawValue, "Binance")
        XCTAssertEqual(Exchange.bithumb.rawValue, "Bithumb")
        XCTAssertEqual(Exchange.bybit.rawValue, "Bybit")
        XCTAssertEqual(Exchange.coinone.rawValue, "Coinone")
        XCTAssertEqual(Exchange.korbit.rawValue, "Korbit")
        XCTAssertEqual(Exchange.okx.rawValue, "OKX")
    }

    func testExchangeCaseIterable() {
        XCTAssertEqual(Exchange.allCases.count, 7)
    }

    func testExchangeInitFromRawValue() {
        XCTAssertEqual(Exchange(rawValue: "Upbit"), .upbit)
        XCTAssertEqual(Exchange(rawValue: "Binance"), .binance)
        XCTAssertEqual(Exchange(rawValue: "OKX"), .okx)
        XCTAssertNil(Exchange(rawValue: "unknown"))
    }

    func testExchangeAllCasesContainsExpected() {
        let expected: Set<Exchange> = [.upbit, .binance, .bithumb, .bybit, .coinone, .korbit, .okx]
        let actual = Set(Exchange.allCases)
        XCTAssertEqual(actual, expected)
    }
}
