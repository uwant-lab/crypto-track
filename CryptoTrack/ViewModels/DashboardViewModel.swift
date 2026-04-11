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

/// 거래소별 fetch 결과 추적.
///
/// `status` / `lastError`는 **자산(balance) 조회** 결과를 나타낸다 —
/// 이 단계가 실패하면 해당 거래소의 어떤 코인도 대시보드에 뜨지 않는다.
///
/// `tickerError`는 **시세 조회** 실패 메시지를 별도로 담는다. 자산은
/// 성공적으로 받았지만 시세(현재가/변동률)만 못 받은 경우 — 이때 UI는
/// 행 자체는 표시하되 현재가/평가금액 칸을 "—"로 렌더한다. 시세 실패는
/// 사용자 입장에서 "현재가가 왜 안 보이지?" 로 나타나므로 반드시 배너로
/// 노출해야 한다.
struct ExchangeFetchStatus: Identifiable, Hashable, Sendable {
    let id: Exchange
    var status: Status
    var lastError: String?
    var tickerError: String?

    enum Status: Sendable, Hashable {
        case loading, success, failed
    }

    /// 시세 조회 실패 여부 (자산 조회와 무관하게).
    var hasTickerFailure: Bool { tickerError != nil }
}

/// A contiguous group of `PortfolioRow`s in the dashboard list, bounded by a
/// single `QuoteCurrency`. When the filter is `.all`, the view model emits
/// one section per currency present in the portfolio. When a single exchange
/// is selected, exactly one section is emitted (for that exchange's currency).
struct RowSection: Identifiable, Sendable {
    var id: QuoteCurrency
    var rows: [PortfolioRow]
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

    /// Sort state for the KRW section in the new `AssetTableSections` view.
    /// The default order mirrors the pre-refactor behaviour.
    var krwSortOrder: [KeyPathComparator<PortfolioRow>] = [
        KeyPathComparator(\PortfolioRow.currentValue, order: .reverse)
    ]

    /// Sort state for the USDT section in the new `AssetTableSections` view.
    var usdSortOrder: [KeyPathComparator<PortfolioRow>] = [
        KeyPathComparator(\PortfolioRow.currentValue, order: .reverse)
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

    private func matchesFilter(_ asset: Asset) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .exchange(let exchange):
            return asset.exchange == exchange
        }
    }

    // MARK: - Display Sections (new sectioned API)

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

    /// Flat view of all rows across all sections. Preserved so that existing
    /// `DashboardViewModelTests` cases can assert on row counts and ordering
    /// without having to walk section by section.
    var displayedRows: [PortfolioRow] {
        displayedSections.flatMap(\.rows)
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
        // 거래소별 ticker 실패를 statuses에 기록. 자산은 받았는데 시세만
        // 못 받으면 현재가/평가금액이 "—"로 표시되므로 사용자에게
        // 알려야 한다 — 말없이 현재가만 "—"이면 원인을 짐작할 수 없다.
        var tickerErrorsByExchange: [Exchange: String] = [:]
        for (exchange, result) in tickerResults {
            switch result {
            case .success(let list):
                newTickers.append(contentsOf: list)
            case .failure(let error):
                tickerErrorsByExchange[exchange] = error.localizedDescription
            }
        }
        if !tickerErrorsByExchange.isEmpty {
            for idx in statuses.indices {
                if let err = tickerErrorsByExchange[statuses[idx].id] {
                    statuses[idx].tickerError = err
                }
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
