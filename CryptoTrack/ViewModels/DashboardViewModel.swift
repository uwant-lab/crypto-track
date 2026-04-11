import Foundation
import Observation

/// CurrencySummary — 통화 그룹별 합계
struct CurrencySummary: Equatable, Sendable {
    let currency: QuoteCurrency
    let totalValue: Double
    let totalCost: Double
    let totalProfit: Double
    let profitRate: Double
    let hasUnknownCostBasis: Bool
}

/// 거래소별 fetch 결과 추적
struct ExchangeFetchStatus: Identifiable, Hashable, Sendable {
    let id: Exchange
    var status: Status
    var lastError: String?

    enum Status: Sendable, Hashable {
        case loading, success, failed
    }
}

/// 대시보드 화면의 상태와 비즈니스 로직을 관리합니다.
@Observable
@MainActor
final class DashboardViewModel {

    // MARK: - Raw Data

    var assets: [Asset] = []
    var tickers: [Ticker] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var exchangeStatuses: [ExchangeFetchStatus] = []

    // MARK: - UI State

    var selectedFilter: ExchangeFilter = .all
    var hideDust: Bool = true

    /// macOS Table에 양방향 바인딩되는 정렬 상태. iOS는 기본값(평가금액 내림차순)만 사용.
    var tableSortOrder: [KeyPathComparator<AssetRow>] = [
        KeyPathComparator(\AssetRow.currentValue, order: .reverse)
    ]

    var lastRefreshDate: Date?

    // MARK: - Constants

    private static let dustThresholdKRW: Double = 1_000
    private static let dustThresholdUSD: Double = 1
    private static let autoRefreshInterval: Duration = .seconds(30)

    // MARK: - Dependencies

    private let exchangeManager: ExchangeManager

    init(exchangeManager: ExchangeManager = .shared) {
        self.exchangeManager = exchangeManager
    }

    // MARK: - Ticker Matching (fallback 제거 — 정확 매치만)

    /// 거래소+심볼이 정확히 일치하는 ticker만 반환한다.
    /// 이전 코드는 같은 심볼이면 다른 거래소 ticker로 fallback했지만, 그 동작은
    /// BTC@Binance(USDT)를 BTC@Upbit(KRW)로 잘못 매칭하는 버그를 만들었다.
    func ticker(for asset: Asset) -> Ticker? {
        tickers.first { $0.symbol == asset.symbol && $0.exchange == asset.exchange }
    }

    /// ticker가 없으면 0 반환. 이전 코드의 totalCost fallback은 제거됨 —
    /// "총 평가액이 매수금액으로 표시" 버그의 본질적 원인이었다.
    func currentValue(for asset: Asset) -> Double {
        guard let ticker = ticker(for: asset) else { return 0 }
        return asset.balance * ticker.currentPrice
    }

    // MARK: - Display Rows (filter → dust → sort)

    /// 필터/dust 적용 후 정렬된 표시용 행 목록.
    var displayedRows: [AssetRow] {
        let rows = assets
            .filter { matchesFilter($0) }
            .map { makeRow(for: $0) }
            .filter { !hideDust || !isDust($0) }
        return rows.sorted(using: tableSortOrder)
    }

    private func matchesFilter(_ asset: Asset) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .exchange(let exchange):
            return asset.exchange == exchange
        }
    }

    private func makeRow(for asset: Asset) -> AssetRow {
        let ticker = ticker(for: asset)
        let currentPrice = ticker?.currentPrice ?? 0
        let value = asset.balance * currentPrice
        let cost = asset.balance * asset.averageBuyPrice
        let profit: Double
        let rate: Double
        if asset.hasCostBasis {
            profit = value - cost
            rate = cost > 0 ? (profit / cost) * 100 : 0
        } else {
            profit = 0
            rate = 0
        }
        return AssetRow(
            id: asset.id,
            asset: asset,
            symbol: asset.symbol,
            exchange: asset.exchange,
            balance: asset.balance,
            averageBuyPrice: asset.averageBuyPrice,
            currentPrice: currentPrice,
            currentValue: value,
            profit: profit,
            profitRate: rate,
            hasCostBasis: asset.hasCostBasis,
            hasTicker: ticker != nil,
            quoteCurrency: asset.quoteCurrency
        )
    }

    /// ticker를 모르면 가치를 모르므로 dust로 분류하지 않는다.
    private func isDust(_ row: AssetRow) -> Bool {
        guard row.hasTicker else { return false }
        let threshold: Double = row.quoteCurrency == .krw
            ? Self.dustThresholdKRW
            : Self.dustThresholdUSD
        return row.currentValue < threshold
    }

    // MARK: - Currency-grouped Summaries

    /// 현재 필터 적용 후 KRW 통화 그룹의 합계. dust는 시각적으로 숨겨도 합산엔 포함.
    var krwSummary: CurrencySummary? { summary(for: .krw) }

    var usdSummary: CurrencySummary? { summary(for: .usdt) }

    private func summary(for currency: QuoteCurrency) -> CurrencySummary? {
        let group = assets
            .filter { matchesFilter($0) }
            .filter { $0.quoteCurrency == currency }
        guard !group.isEmpty else { return nil }

        let value = group.reduce(0.0) { $0 + currentValue(for: $1) }
        let cost = group.reduce(0.0) { partial, asset in
            asset.hasCostBasis ? partial + (asset.balance * asset.averageBuyPrice) : partial
        }
        let hasUnknown = group.contains { !$0.hasCostBasis }
        let profit = value - cost
        let rate: Double = cost > 0 ? (profit / cost) * 100 : 0

        return CurrencySummary(
            currency: currency,
            totalValue: value,
            totalCost: cost,
            totalProfit: profit,
            profitRate: rate,
            hasUnknownCostBasis: hasUnknown
        )
    }

    // MARK: - Auto-refresh Loop

    /// SwiftUI `.task` 모디파이어에서 호출. View가 사라지면 자동 cancel된다.
    func runAutoRefreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.autoRefreshInterval)
            } catch {
                break  // CancellationError
            }
            await refresh()
        }
    }

    // MARK: - Refresh (per-exchange status tracking)

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

        // 모든 거래소 실패 + 자산 없음 → 전체 에러
        if newAssets.isEmpty && !statuses.isEmpty && statuses.allSatisfy({ $0.status == .failed }) {
            errorMessage = "모든 거래소에서 데이터를 불러오지 못했습니다."
        }
    }

    // MARK: - Sample Data (preview용)

    static let sampleAssets: [Asset] = [
        Asset(id: "upbit-BTC", symbol: "BTC", balance: 0.5, averageBuyPrice: 55_000_000, exchange: .upbit, lastUpdated: Date()),
        Asset(id: "upbit-ETH", symbol: "ETH", balance: 3.2, averageBuyPrice: 2_800_000, exchange: .upbit, lastUpdated: Date()),
        Asset(id: "binance-BTC", symbol: "BTC", balance: 0.25, averageBuyPrice: 0, exchange: .binance, lastUpdated: Date()),
        Asset(id: "binance-ETH", symbol: "ETH", balance: 1.8, averageBuyPrice: 0, exchange: .binance, lastUpdated: Date()),
    ]

    static let sampleTickers: [Ticker] = [
        Ticker(id: "upbit-BTC-ticker", symbol: "BTC", currentPrice: 62_000_000, changeRate24h: 2.35, volume24h: 1_500_000_000, exchange: .upbit, timestamp: Date()),
        Ticker(id: "upbit-ETH-ticker", symbol: "ETH", currentPrice: 3_100_000, changeRate24h: -1.12, volume24h: 800_000_000, exchange: .upbit, timestamp: Date()),
        Ticker(id: "binance-BTC-ticker", symbol: "BTC", currentPrice: 47_500, changeRate24h: 2.41, volume24h: 25_000, exchange: .binance, timestamp: Date()),
        Ticker(id: "binance-ETH-ticker", symbol: "ETH", currentPrice: 2_380, changeRate24h: -0.98, volume24h: 18_000, exchange: .binance, timestamp: Date()),
    ]

    static var preview: DashboardViewModel {
        let vm = DashboardViewModel(exchangeManager: ExchangeManager())
        vm.assets = sampleAssets
        vm.tickers = sampleTickers
        vm.hideDust = false
        return vm
    }
}
