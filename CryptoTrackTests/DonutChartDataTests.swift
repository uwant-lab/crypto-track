// CryptoTrackTests/DonutChartDataTests.swift
import XCTest
@testable import CryptoTrack

@MainActor
final class DonutChartDataTests: XCTestCase {

    private var viewModel: DashboardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = DashboardViewModel(exchangeManager: ExchangeManager())
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    private func makeAsset(
        symbol: String, balance: Double, avgPrice: Double, exchange: Exchange
    ) -> Asset {
        Asset(
            id: "\(exchange.rawValue)-\(symbol)",
            symbol: symbol, balance: balance,
            averageBuyPrice: avgPrice, exchange: exchange, lastUpdated: Date()
        )
    }

    private func makeTicker(
        symbol: String, price: Double, exchange: Exchange
    ) -> Ticker {
        Ticker(
            id: "\(exchange.rawValue)-\(symbol)-ticker",
            symbol: symbol, currentPrice: price,
            changeRate24h: 0, volume24h: 0,
            exchange: exchange, timestamp: Date()
        )
    }

    // MARK: - Allocation slices

    func testAllocationSlicesCalculatesPercentages() {
        viewModel.assets = [
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 50_000_000, exchange: .upbit),
            makeAsset(symbol: "ETH", balance: 2, avgPrice: 2_000_000, exchange: .upbit),
        ]
        viewModel.tickers = [
            makeTicker(symbol: "BTC", price: 60_000_000, exchange: .upbit),
            makeTicker(symbol: "ETH", price: 3_000_000, exchange: .upbit),
        ]
        viewModel.hideDust = false

        let slices = viewModel.allocationSlices(for: .krw)
        XCTAssertEqual(slices.count, 2)
        // BTC: 60M / (60M + 6M) = 90.91%
        // ETH: 6M / 66M = 9.09%
        XCTAssertEqual(slices[0].symbol, "BTC")
        XCTAssertEqual(slices[0].percentage, 90.91, accuracy: 0.01)
        XCTAssertEqual(slices[1].symbol, "ETH")
        XCTAssertEqual(slices[1].percentage, 9.09, accuracy: 0.01)
    }

    func testAllocationSlicesSortedByValueDescending() {
        viewModel.assets = [
            makeAsset(symbol: "ETH", balance: 1, avgPrice: 1, exchange: .upbit),
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 1, exchange: .upbit),
        ]
        viewModel.tickers = [
            makeTicker(symbol: "ETH", price: 3_000_000, exchange: .upbit),
            makeTicker(symbol: "BTC", price: 60_000_000, exchange: .upbit),
        ]
        viewModel.hideDust = false

        let slices = viewModel.allocationSlices(for: .krw)
        XCTAssertEqual(slices.map(\.symbol), ["BTC", "ETH"])
    }

    func testAllocationSlicesRespectsHideDust() {
        viewModel.assets = [
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 50_000_000, exchange: .upbit),
            makeAsset(symbol: "DOGE", balance: 0.001, avgPrice: 500_000, exchange: .upbit),
        ]
        viewModel.tickers = [
            makeTicker(symbol: "BTC", price: 60_000_000, exchange: .upbit),
            makeTicker(symbol: "DOGE", price: 500_000, exchange: .upbit),
        ]
        viewModel.hideDust = true

        let slices = viewModel.allocationSlices(for: .krw)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].symbol, "BTC")
        XCTAssertEqual(slices[0].percentage, 100.0, accuracy: 0.01)
    }

    func testAllocationSlicesEmptyWhenNoAssets() {
        viewModel.assets = []
        viewModel.tickers = []

        let slices = viewModel.allocationSlices(for: .krw)
        XCTAssertTrue(slices.isEmpty)
    }

    func testAllocationSlicesOnlyIncludesMatchingCurrency() {
        viewModel.assets = [
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 50_000_000, exchange: .upbit),
            makeAsset(symbol: "SOL", balance: 10, avgPrice: 100, exchange: .binance),
        ]
        viewModel.tickers = [
            makeTicker(symbol: "BTC", price: 60_000_000, exchange: .upbit),
            makeTicker(symbol: "SOL", price: 150, exchange: .binance),
        ]
        viewModel.hideDust = false

        let krwSlices = viewModel.allocationSlices(for: .krw)
        XCTAssertEqual(krwSlices.count, 1)
        XCTAssertEqual(krwSlices[0].symbol, "BTC")

        let usdSlices = viewModel.allocationSlices(for: .usdt)
        XCTAssertEqual(usdSlices.count, 1)
        XCTAssertEqual(usdSlices[0].symbol, "SOL")
    }

    func testAllocationSlicesRespectsExchangeFilter() {
        viewModel.assets = [
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 50_000_000, exchange: .upbit),
            makeAsset(symbol: "ETH", balance: 2, avgPrice: 2_000_000, exchange: .bithumb),
        ]
        viewModel.tickers = [
            makeTicker(symbol: "BTC", price: 60_000_000, exchange: .upbit),
            makeTicker(symbol: "ETH", price: 3_000_000, exchange: .bithumb),
        ]
        viewModel.selectedFilter = .exchange(.upbit)
        viewModel.hideDust = false

        let slices = viewModel.allocationSlices(for: .krw)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].symbol, "BTC")
    }

    func testAllocationSlicesZeroValueAssetsExcluded() {
        viewModel.assets = [
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 50_000_000, exchange: .upbit),
            makeAsset(symbol: "ETH", balance: 2, avgPrice: 2_000_000, exchange: .upbit),
        ]
        // ETH has no ticker → currentValue == 0
        viewModel.tickers = [
            makeTicker(symbol: "BTC", price: 60_000_000, exchange: .upbit),
        ]
        viewModel.hideDust = false

        let slices = viewModel.allocationSlices(for: .krw)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].symbol, "BTC")
        XCTAssertEqual(slices[0].percentage, 100.0, accuracy: 0.01)
    }
}
