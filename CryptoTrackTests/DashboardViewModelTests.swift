// CryptoTrackTests/DashboardViewModelTests.swift
import XCTest
@testable import CryptoTrack

@MainActor
final class DashboardViewModelTests: XCTestCase {

    private var viewModel: DashboardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        // ExchangeManager는 사용하지 않음 — assets/tickers를 직접 주입
        viewModel = DashboardViewModel(exchangeManager: ExchangeManager())
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeAsset(
        symbol: String,
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

    private func makeTicker(
        symbol: String,
        price: Double,
        exchange: Exchange
    ) -> Ticker {
        Ticker(
            id: "\(exchange.rawValue)-\(symbol)-ticker",
            symbol: symbol,
            currentPrice: price,
            changeRate24h: 0,
            volume24h: 0,
            exchange: exchange,
            timestamp: Date()
        )
    }

    // MARK: - Ticker matching (regression for the cost-basis fallback bug)

    /// 시세가 없는 자산은 currentValue가 0이어야 한다 (이전 코드는 totalCost로 fallback했음).
    func testCurrentValueIsZeroWhenTickerMissing() {
        let asset = makeAsset(symbol: "BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit)
        viewModel.assets = [asset]
        viewModel.tickers = []

        XCTAssertEqual(viewModel.currentValue(for: asset), 0)
    }

    /// 거래소가 다른 같은 심볼 ticker로 fallback하지 않는다.
    func testTickerMatchingRequiresExactExchange() {
        let upbitBTC = makeAsset(symbol: "BTC", balance: 1.0, avgPrice: 55_000_000, exchange: .upbit)
        let binanceTicker = makeTicker(symbol: "BTC", price: 60_000, exchange: .binance)
        viewModel.assets = [upbitBTC]
        viewModel.tickers = [binanceTicker]

        // upbit BTC는 binance ticker로 매칭되면 안 됨
        XCTAssertNil(viewModel.ticker(for: upbitBTC))
        XCTAssertEqual(viewModel.currentValue(for: upbitBTC), 0)
    }

    /// 정확한 거래소+심볼 매치는 currentValue를 계산한다.
    func testCurrentValueIsBalanceTimesTickerPrice() {
        let asset = makeAsset(symbol: "BTC", balance: 0.5, avgPrice: 55_000_000, exchange: .upbit)
        let ticker = makeTicker(symbol: "BTC", price: 62_000_000, exchange: .upbit)
        viewModel.assets = [asset]
        viewModel.tickers = [ticker]

        XCTAssertEqual(viewModel.currentValue(for: asset), 31_000_000, accuracy: 0.001)
    }

    // MARK: - Filtering

    func testFilterAllReturnsAllAssets() {
        viewModel.assets = [
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 1, exchange: .upbit),
            makeAsset(symbol: "ETH", balance: 1, avgPrice: 1, exchange: .bithumb),
        ]
        viewModel.tickers = [
            makeTicker(symbol: "BTC", price: 100_000, exchange: .upbit),
            makeTicker(symbol: "ETH", price: 100_000, exchange: .bithumb),
        ]
        viewModel.selectedFilter = .all
        viewModel.hideDust = false

        XCTAssertEqual(viewModel.displayedRows.count, 2)
    }

    func testFilterByExchangeReturnsOnlyThatExchange() {
        viewModel.assets = [
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 1, exchange: .upbit),
            makeAsset(symbol: "ETH", balance: 1, avgPrice: 1, exchange: .bithumb),
        ]
        viewModel.tickers = [
            makeTicker(symbol: "BTC", price: 100_000, exchange: .upbit),
            makeTicker(symbol: "ETH", price: 100_000, exchange: .bithumb),
        ]
        viewModel.selectedFilter = .exchange(.upbit)
        viewModel.hideDust = false

        XCTAssertEqual(viewModel.displayedRows.count, 1)
        XCTAssertEqual(viewModel.displayedRows.first?.exchange, .upbit)
    }

    // MARK: - Dust filtering

    func testDustHiddenWhenBelowKRWThreshold() {
        // 0.001 * 500,000 = 500 KRW (< 1,000 임계값)
        let asset = makeAsset(symbol: "DOGE", balance: 0.001, avgPrice: 500_000, exchange: .upbit)
        let ticker = makeTicker(symbol: "DOGE", price: 500_000, exchange: .upbit)
        viewModel.assets = [asset]
        viewModel.tickers = [ticker]
        viewModel.hideDust = true

        XCTAssertTrue(viewModel.displayedRows.isEmpty)
    }

    func testDustVisibleWhenToggleOff() {
        let asset = makeAsset(symbol: "DOGE", balance: 0.001, avgPrice: 500_000, exchange: .upbit)
        let ticker = makeTicker(symbol: "DOGE", price: 500_000, exchange: .upbit)
        viewModel.assets = [asset]
        viewModel.tickers = [ticker]
        viewModel.hideDust = false

        XCTAssertEqual(viewModel.displayedRows.count, 1)
    }

    /// ticker가 없는 자산은 가치를 모르므로 dust로 분류하지 않는다 (숨기지 않음).
    func testAssetWithoutTickerIsNotDust() {
        let asset = makeAsset(symbol: "DOGE", balance: 0.001, avgPrice: 500_000, exchange: .upbit)
        viewModel.assets = [asset]
        viewModel.tickers = []  // ticker fetch 실패
        viewModel.hideDust = true

        XCTAssertEqual(viewModel.displayedRows.count, 1)
    }

    // MARK: - Currency-grouped summary

    func testKRWSummarySumsKoreanExchangesOnly() {
        let upbitBTC = makeAsset(symbol: "BTC", balance: 1.0, avgPrice: 50_000_000, exchange: .upbit)
        let bithumbETH = makeAsset(symbol: "ETH", balance: 2.0, avgPrice: 2_000_000, exchange: .bithumb)
        let binanceSOL = makeAsset(symbol: "SOL", balance: 10, avgPrice: 100, exchange: .binance)
        viewModel.assets = [upbitBTC, bithumbETH, binanceSOL]
        viewModel.tickers = [
            makeTicker(symbol: "BTC", price: 60_000_000, exchange: .upbit),
            makeTicker(symbol: "ETH", price: 3_000_000, exchange: .bithumb),
            makeTicker(symbol: "SOL", price: 150, exchange: .binance),
        ]
        viewModel.selectedFilter = .all

        let krw = viewModel.krwSummary
        XCTAssertNotNil(krw)
        // 60M + 6M = 66M
        XCTAssertEqual(krw?.totalValue ?? 0, 66_000_000, accuracy: 0.001)
        // 50M + 4M = 54M
        XCTAssertEqual(krw?.totalCost ?? 0, 54_000_000, accuracy: 0.001)
        XCTAssertEqual(krw?.totalProfit ?? 0, 12_000_000, accuracy: 0.001)
        XCTAssertFalse(krw?.hasUnknownCostBasis ?? true)
    }

    func testUSDSummaryIncludesUnknownCostFlag() {
        let binanceSOL = makeAsset(symbol: "SOL", balance: 10, avgPrice: 0, exchange: .binance)
        viewModel.assets = [binanceSOL]
        viewModel.tickers = [makeTicker(symbol: "SOL", price: 150, exchange: .binance)]

        let usd = viewModel.usdSummary
        XCTAssertNotNil(usd)
        XCTAssertEqual(usd?.totalValue ?? 0, 1_500, accuracy: 0.001)
        XCTAssertEqual(usd?.totalCost ?? 0, 0)
        XCTAssertEqual(usd?.profitRate ?? -1, 0)  // cost == 0 → 0
        XCTAssertTrue(usd?.hasUnknownCostBasis ?? false)
    }

    /// 필터로 한쪽 통화만 남으면 반대편 summary는 nil
    func testSummaryNilWhenNoAssetsForCurrency() {
        viewModel.assets = [
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 1, exchange: .upbit),
        ]
        viewModel.tickers = [makeTicker(symbol: "BTC", price: 100, exchange: .upbit)]
        viewModel.selectedFilter = .exchange(.upbit)

        XCTAssertNotNil(viewModel.krwSummary)
        XCTAssertNil(viewModel.usdSummary)
    }

    /// dust도 summary 합산엔 포함된다 (시각적으로만 숨김).
    func testSummaryIncludesDustAssets() {
        let big = makeAsset(symbol: "BTC", balance: 1, avgPrice: 50_000_000, exchange: .upbit)
        let dust = makeAsset(symbol: "DOGE", balance: 0.001, avgPrice: 500_000, exchange: .upbit)
        viewModel.assets = [big, dust]
        viewModel.tickers = [
            makeTicker(symbol: "BTC", price: 60_000_000, exchange: .upbit),
            makeTicker(symbol: "DOGE", price: 500_000, exchange: .upbit),
        ]
        viewModel.hideDust = true

        // 표시는 1개 (dust 숨김)
        XCTAssertEqual(viewModel.displayedRows.count, 1)
        // 합산은 dust 포함 — 60_000_000 + 500 = 60_000_500
        XCTAssertEqual(viewModel.krwSummary?.totalValue ?? 0, 60_000_500, accuracy: 0.001)
    }

    // MARK: - Sort order (default: currentValue desc)

    func testDefaultSortIsCurrentValueDescending() {
        viewModel.assets = [
            makeAsset(symbol: "ETH", balance: 1, avgPrice: 1, exchange: .upbit),
            makeAsset(symbol: "BTC", balance: 1, avgPrice: 1, exchange: .upbit),
            makeAsset(symbol: "SOL", balance: 1, avgPrice: 1, exchange: .upbit),
        ]
        viewModel.tickers = [
            makeTicker(symbol: "ETH", price: 3_000_000, exchange: .upbit),
            makeTicker(symbol: "BTC", price: 60_000_000, exchange: .upbit),
            makeTicker(symbol: "SOL", price: 200_000, exchange: .upbit),
        ]
        viewModel.hideDust = false

        let symbols = viewModel.displayedRows.map(\.symbol)
        XCTAssertEqual(symbols, ["BTC", "ETH", "SOL"])
    }
}
