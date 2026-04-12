# 대시보드 로직 개선 및 UI 고도화 설계

## 개요

거래소 통합 대시보드의 자산 표시 로직을 정확히 다듬고, 거래소별 필터링과 코인별 상세 테이블을 추가한다. 기존 ExchangeManager·Service 계층은 그대로 두고 DashboardViewModel과 View 컴포넌트만 확장한다.

## 배경

현재 대시보드는 다음 문제가 있다:

1. **시세 매칭 fallback 버그**: `currentValue(for:)`가 ticker fetch 실패 시 `asset.totalCost`로 fallback해서, 시세 fetch가 실패한 거래소의 총 평가액이 매수금액과 같게 표시된다. 사용자에게는 "총 평가액이 잘못 계산된다"로 보인다.
2. **거래소 간 ticker 오매칭**: `ticker(for:)`가 거래소가 다른 같은 심볼 ticker로 fallback해서, 예를 들어 BTC@Binance(USDT)를 BTC@Upbit(KRW) ticker로 잘못 매칭할 수 있다.
3. **단일 통화 합산의 의미 부재**: 국내 거래소(KRW)와 해외 거래소(USDT) 자산을 단순 합산하면 의미 없는 숫자가 나온다.
4. **단순 UI**: 거래소별 필터, 코인별 상세 정보(보유량/평단가/현재가/수익률), 정렬, dust 필터 같은 기본 기능이 없다.

## 범위

### 포함

- 거래소 필터 탭 (전체 + 등록된 거래소만 동적 표시)
- KRW/USD 두 줄로 분리된 통화별 요약 카드
- 자산 테이블 — macOS는 컴팩트 테이블, iOS는 카드형 행 (플랫폼 분기)
- 컬럼: 코인, 보유량, 평단가, 현재가, 평가금액, 수익률
- 정렬: 평가금액 내림차순 기본, macOS는 컬럼 헤더 클릭으로 재정렬
- Dust 필터: 평가액 ₩1,000(또는 $1) 미만 자동 숨김 + 토글
- 30초 자동 갱신 + 풀투리프레시
- 색상 모드: 한국 기본(빨/파), 설정에서 글로벌(초록/빨)로 전환 가능
- 해외 거래소 자산의 평단가/수익률은 "—"(N/A) 표시
- 시세 fetch 실패 시 fallback 제거 (정확한 계산 우선)
- 거래소별 fetch 상태 추적 (일부 실패 시 사용자 알림 배너)

### 제외 (YAGNI)

- 환율 API 연동 (USD↔KRW 환산)
- 사용자가 평단가 수동 입력
- dust 임계값 사용자 설정
- 자동 갱신 주기 사용자 설정
- 컬럼 가시성/순서 커스터마이즈
- 거래소 그룹별 묶음 표시
- iCloud 동기화에 priceColorMode 통합 (UserDefaults 로컬만)

---

## 데이터 모델

### 1) `Exchange` enum 확장

거래소가 가진 통화 단위를 표현. 통화 그룹화의 단일 원천이다.

```swift
enum QuoteCurrency: String, Sendable {
    case krw, usdt

    var symbol: String { self == .krw ? "₩" : "$" }
    var displayName: String { self == .krw ? "KRW" : "USD" }
}

extension Exchange {
    var quoteCurrency: QuoteCurrency {
        switch self {
        case .upbit, .bithumb, .coinone, .korbit:
            return .krw
        case .binance, .bybit, .okx:
            return .usdt
        }
    }
}
```

### 2) `Asset` 모델 헬퍼 (저장 속성 추가 없음)

```swift
extension Asset {
    /// 평단가가 0이면 cost basis 미제공으로 간주 (해외 거래소)
    var hasCostBasis: Bool { averageBuyPrice > 0 }

    var quoteCurrency: QuoteCurrency { exchange.quoteCurrency }
}
```

`totalCost`는 이미 모델에 있다고 가정 (현재 ViewModel에서 사용 중). 없다면 같은 extension에 추가.

### 3) 새 enum

```swift
enum ExchangeFilter: Hashable {
    case all
    case exchange(Exchange)
}
```

정렬은 아래 정의되는 `AssetRow`에 SwiftUI `KeyPathComparator`를 적용해서 처리한다. 별도의 SortKey enum은 두지 않는다 — `AssetRow`의 KeyPath 자체가 정렬 키 역할을 한다. macOS는 `Table`이 컬럼 헤더 클릭 정렬을 자동 지원한다.

### 4) `CurrencySummary` — 요약 카드 한 행의 데이터

```swift
struct CurrencySummary: Equatable {
    let currency: QuoteCurrency
    let totalValue: Double
    let totalCost: Double
    let totalProfit: Double      // value - cost
    let profitRate: Double       // %
    let hasUnknownCostBasis: Bool  // 해외 거래소 자산이 섞여있으면 true
}
```

### 5) `AppSettings` 확장

```swift
struct AppSettings: Codable, Equatable, Sendable {
    var isAppLockEnabled: Bool
    var lastSyncDate: Date?
    var priceColorMode: PriceColorMode = .korean
}

enum PriceColorMode: String, Codable, Sendable {
    case korean   // 상승=빨강, 하락=파랑 (기본)
    case global   // 상승=초록, 하락=빨강
}
```

### 6) `ExchangeFetchStatus` — 거래소별 fetch 결과 추적

```swift
struct ExchangeFetchStatus: Identifiable {
    let id: Exchange
    var status: Status
    var lastError: String?

    enum Status { case loading, success, failed }
}
```

---

## DashboardViewModel 동작

### State

```swift
@Observable
@MainActor
final class DashboardViewModel {
    // 원본 데이터
    var assets: [Asset] = []
    var tickers: [Ticker] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var exchangeStatuses: [ExchangeFetchStatus] = []

    // UI 상태
    var selectedFilter: ExchangeFilter = .all
    var hideDust: Bool = true
    /// macOS Table에 양방향 바인딩되는 정렬 상태. iOS는 이 기본값(평가금액 내림차순)만 사용하고 변경하지 않는다.
    var tableSortOrder: [KeyPathComparator<AssetRow>] = [
        KeyPathComparator(\.currentValue, order: .reverse)
    ]
    var lastRefreshDate: Date?

    // 설정 (AppSettingsManager.shared 구독)
    var priceColorMode: PriceColorMode = .korean

    // 자동 갱신
    private static let dustThresholdKRW: Double = 1_000
    private static let dustThresholdUSD: Double = 1
    private static let autoRefreshInterval: Duration = .seconds(30)
}
```

### 시세 매칭 — fallback 제거 (버그 수정)

```swift
func ticker(for asset: Asset) -> Ticker? {
    // 거래소까지 정확히 일치할 때만. 이전 코드의 "심볼만 일치" fallback은 제거.
    tickers.first { $0.symbol == asset.symbol && $0.exchange == asset.exchange }
}

func currentValue(for asset: Asset) -> Double {
    // ⚠️ ticker 없으면 0 반환 (이전 코드의 totalCost fallback 제거)
    guard let ticker = ticker(for: asset) else { return 0 }
    return asset.balance * ticker.currentPrice
}
```

이 두 가지 변경이 사용자가 신고한 "총 평가액이 매수금액으로 표시" 버그의 본질적 해결이다.

### 표시용 행 목록 (필터 → dust → 정렬)

`AssetRow`로 한 번 변환해서 ticker 기반 값(currentPrice/currentValue/profitRate)을 평탄화한다. 이렇게 하면 `KeyPathComparator`를 단순 KeyPath로 사용할 수 있고, macOS Table의 sortable column 기능이 그대로 작동한다.

```swift
struct AssetRow: Identifiable, Hashable {
    let id: String         // asset.id
    let asset: Asset
    let symbol: String
    let balance: Double
    let averageBuyPrice: Double
    let currentPrice: Double  // 0 if no ticker
    let currentValue: Double  // balance * currentPrice
    let profit: Double        // currentValue - balance * averageBuyPrice
    let profitRate: Double    // 0 if no cost basis
    let hasCostBasis: Bool
    let hasTicker: Bool
}

var displayedRows: [AssetRow] {
    let filtered = assets
        .filter { matchesFilter($0) }
        .map { makeRow(for: $0) }
        .filter { !hideDust || !isDust($0) }
    return filtered.sorted(using: tableSortOrder)
}

private func matchesFilter(_ asset: Asset) -> Bool {
    switch selectedFilter {
    case .all: return true
    case .exchange(let ex): return asset.exchange == ex
    }
}

private func makeRow(for asset: Asset) -> AssetRow {
    let ticker = ticker(for: asset)
    let currentPrice = ticker?.currentPrice ?? 0
    let value = asset.balance * currentPrice
    let cost = asset.balance * asset.averageBuyPrice
    let profit = asset.hasCostBasis ? value - cost : 0
    let rate: Double = asset.hasCostBasis && cost > 0 ? (profit / cost) * 100 : 0
    return AssetRow(
        id: asset.id,
        asset: asset,
        symbol: asset.symbol,
        balance: asset.balance,
        averageBuyPrice: asset.averageBuyPrice,
        currentPrice: currentPrice,
        currentValue: value,
        profit: profit,
        profitRate: rate,
        hasCostBasis: asset.hasCostBasis,
        hasTicker: ticker != nil
    )
}

/// 시세를 모르는 자산은 dust로 분류하지 않는다 (값을 모르면 숨기지도 않음).
private func isDust(_ row: AssetRow) -> Bool {
    guard row.hasTicker else { return false }
    let threshold: Double = row.asset.quoteCurrency == .krw
        ? Self.dustThresholdKRW
        : Self.dustThresholdUSD
    return row.currentValue < threshold
}
```

### 통화별 요약 합산

요약은 **dust도 포함** (시각적으로만 숨김). 필터(`selectedFilter`)는 적용. 즉 "필터 적용 후 dust 포함 자산 전체"로 합산한다.

```swift
var krwSummary: CurrencySummary? { summary(for: .krw) }
var usdSummary: CurrencySummary? { summary(for: .usdt) }

private func summary(for currency: QuoteCurrency) -> CurrencySummary? {
    let group = assets
        .filter { matchesFilter($0) }
        .filter { $0.quoteCurrency == currency }
    guard !group.isEmpty else { return nil }

    let value = group.reduce(0) { $0 + currentValue(for: $1) }
    let cost = group.reduce(0) { $0 + ($1.hasCostBasis ? $1.balance * $1.averageBuyPrice : 0) }
    let hasUnknown = group.contains { !$0.hasCostBasis }
    let rate: Double = cost > 0 ? ((value - cost) / cost) * 100 : 0

    return CurrencySummary(
        currency: currency,
        totalValue: value,
        totalCost: cost,
        totalProfit: value - cost,
        profitRate: rate,
        hasUnknownCostBasis: hasUnknown
    )
}
```

### 자동 갱신

```swift
/// SwiftUI .task에서 호출. 뷰가 사라지면 자동 cancel된다.
func runAutoRefreshLoop() async {
    await refresh()
    while !Task.isCancelled {
        do {
            try await Task.sleep(for: Self.autoRefreshInterval)
        } catch {
            break  // cancellation
        }
        await refresh()
    }
}
```

### refresh — 거래소별 결과 추적

```swift
func refresh() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    let assetResults = await exchangeManager.fetchAssetsPerExchange()
    let symbols = Set(assetResults.compactMap {
        if case .success(let list) = $0.1 { return list.map(\.symbol) }
        return nil
    }.flatMap { $0 })
    let tickerResults = await exchangeManager.fetchTickersPerExchange(symbols: Array(symbols))

    var newAssets: [Asset] = []
    var statuses: [ExchangeFetchStatus] = []
    for (ex, result) in assetResults {
        switch result {
        case .success(let list):
            newAssets.append(contentsOf: list)
            statuses.append(.init(id: ex, status: .success, lastError: nil))
        case .failure(let err):
            statuses.append(.init(id: ex, status: .failed, lastError: err.localizedDescription))
        }
    }

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

    // 모든 거래소 실패 + 자산 0개면 errorMessage 세팅
    if newAssets.isEmpty && statuses.allSatisfy({ $0.status == .failed }) {
        errorMessage = "모든 거래소에서 데이터를 불러오지 못했습니다."
    }
}
```

---

## ExchangeManager 추가 메서드

기존 `fetchAllAssets`/`fetchAllTickers`는 그대로 둔다. 거래소별 결과를 추적하는 새 메서드 두 개만 추가.

```swift
extension ExchangeManager {
    func fetchAssetsPerExchange() async -> [(Exchange, Result<[Asset], Error>)] {
        await withTaskGroup(of: (Exchange, Result<[Asset], Error>).self) { group in
            for exchange in registeredExchanges {
                guard let service = services[exchange] else { continue }
                group.addTask {
                    do {
                        let list = try await service.fetchAssets()
                        return (exchange, .success(list))
                    } catch {
                        return (exchange, .failure(error))
                    }
                }
            }
            var results: [(Exchange, Result<[Asset], Error>)] = []
            for await item in group { results.append(item) }
            return results
        }
    }

    func fetchTickersPerExchange(symbols: [String]) async -> [(Exchange, Result<[Ticker], Error>)] {
        // 동일 패턴
    }
}
```

---

## View 컴포넌트

### 파일 구조

```
Views/Dashboard/
├── DashboardView.swift               # 컨테이너만 (대폭 축소)
├── AssetFilterTabBar.swift           # 신규
├── PortfolioSummaryCard.swift        # 기존 PortfolioSummaryView 개편
├── DashboardToolbar.swift            # 신규 — dust 토글 + 갱신 시각 + 새로고침
├── AssetTable.swift                  # 신규 — macOS Table
├── AssetCardList.swift               # 신규 — iOS 카드 List
├── ExchangeStatusBanner.swift        # 신규 — 일부 fetch 실패 알림
└── Components/
    ├── PriceColor.swift              # 색상 모드 헬퍼
    ├── ProfitBadge.swift             # 수익률 칩
    └── PriceFormatter.swift          # 통화별 숫자 포맷
```

### DashboardView (컨테이너)

```swift
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("대시보드")
                .task { await viewModel.runAutoRefreshLoop() }
                .refreshable { await viewModel.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.assets.isEmpty {
            loadingView
        } else if hasNoExchanges {
            emptyStateView
        } else {
            VStack(spacing: 0) {
                AssetFilterTabBar(
                    selected: $viewModel.selectedFilter,
                    available: registeredExchanges
                )
                PortfolioSummaryCard(
                    krw: viewModel.krwSummary,
                    usd: viewModel.usdSummary,
                    colorMode: viewModel.priceColorMode
                )
                if hasFailedExchanges {
                    ExchangeStatusBanner(statuses: viewModel.exchangeStatuses)
                }
                DashboardToolbar(
                    hideDust: $viewModel.hideDust,
                    lastRefresh: viewModel.lastRefreshDate,
                    isRefreshing: viewModel.isLoading,
                    onRefresh: { Task { await viewModel.refresh() } }
                )
                assetsList
            }
        }
    }

    @ViewBuilder
    private var assetsList: some View {
        if viewModel.displayedRows.isEmpty {
            emptyFilterView
        } else {
            #if os(macOS)
            AssetTable(
                rows: viewModel.displayedRows,
                sortOrder: $viewModel.tableSortOrder,
                colorMode: viewModel.priceColorMode
            )
            #else
            AssetCardList(
                rows: viewModel.displayedRows,
                colorMode: viewModel.priceColorMode
            )
            #endif
        }
    }
}
```

### AssetFilterTabBar — 가로 스크롤 칩

`available: [Exchange]`는 `ExchangeManager.shared.registeredExchanges`에서 가져온다. `FilterChip`은 선택 여부에 따라 배경색을 바꾸는 작은 컴포넌트.

### PortfolioSummaryCard — KRW/USD 두 줄

- `krw == nil && usd == nil` → 카드 자체 안 그림 (필터 결과 없음)
- 한쪽만 있으면 그쪽만 그림
- 둘 다 있으면 Divider로 구분
- 각 행은 좌측 통화/총평가액, 우측 ProfitBadge + (해당되면) "일부 자산 평단가 미제공" 부가 텍스트

### AssetTable (macOS) — SwiftUI Table

`AssetRow`(데이터 모델 섹션에서 정의)를 컬렉션으로 받고, ViewModel의 `tableSortOrder: [KeyPathComparator<AssetRow>]`를 양방향 바인딩으로 받는다. SwiftUI `Table`이 컬럼 헤더 클릭 정렬을 자동 처리하고, ViewModel의 `displayedRows` computed property는 `tableSortOrder` 변경에 따라 자동으로 재계산된다 (`@Observable` 의존성 추적).

```swift
#if os(macOS)
struct AssetTable: View {
    let rows: [AssetRow]
    @Binding var sortOrder: [KeyPathComparator<AssetRow>]
    let colorMode: PriceColorMode

    var body: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("코인") { row in
                AssetSymbolCell(asset: row.asset)
            }
            TableColumn("보유량", value: \.balance) { row in
                Text(formatBalance(row.balance)).monospacedDigit()
            }
            TableColumn("평단가", value: \.averageBuyPrice) { row in
                row.hasCostBasis
                    ? Text(formatPrice(row.averageBuyPrice, currency: row.asset.quoteCurrency)).monospacedDigit()
                    : Text("—").foregroundStyle(.secondary)
            }
            TableColumn("현재가", value: \.currentPrice) { row in
                row.hasTicker
                    ? Text(formatPrice(row.currentPrice, currency: row.asset.quoteCurrency)).monospacedDigit()
                    : Text("—").foregroundStyle(.secondary)
            }
            TableColumn("평가금액", value: \.currentValue) { row in
                Text(formatPrice(row.currentValue, currency: row.asset.quoteCurrency))
                    .monospacedDigit().fontWeight(.semibold)
            }
            TableColumn("수익률", value: \.profitRate) { row in
                row.hasCostBasis
                    ? ProfitBadge(rate: row.profitRate, profit: row.profit, colorMode: colorMode)
                    : Text("—").foregroundStyle(.secondary)
            }
        }
    }
}
#endif
```

### AssetCardList (iOS) — 카드형

`[AssetRow]`를 받아 SwiftUI `List`에 커스텀 셀(`AssetCardRow`)로 렌더링한다. 정렬은 ViewModel의 `tableSortOrder` 기본값(평가금액 내림차순)을 그대로 사용한다 — iOS는 컬럼 정렬 UI가 없으므로 이 값을 변경하지 않는다.

브라우저에서 본 B 디자인 그대로. 각 행은:
- 좌측: 코인 심볼 (큰 글자) + 거래소 + 보유량 (작은 글자)
- 우측: 평가금액 (큰 글자) + 수익률 ProfitBadge
- 하단(divider 아래): "평단 ₩X · 현재가 ₩Y" 보조 정보 (해외 거래소면 평단 부분 "—")

### ExchangeStatusBanner

`exchangeStatuses` 중 `.failed`인 것이 있을 때만 표시. 노란 배경의 작은 배너:

```
⚠️ 1개 거래소 갱신 실패 (Bithumb: 인증 오류)  [재시도]
```

### 색상 모드 (PriceColor 헬퍼)

```swift
enum PriceColor {
    static func color(for value: Double, mode: PriceColorMode) -> Color {
        guard value != 0 else { return .secondary }
        switch mode {
        case .korean: return value > 0 ? .red : .blue
        case .global: return value > 0 ? .green : .red
        }
    }
}
```

`ProfitBadge`는 이 헬퍼를 받아 양수/음수에 따라 전경색을 결정.

### 설정 화면 추가

`SettingsView`에 새 섹션 — "표시 설정":
- 색상 모드 Picker: 한국 (빨/파) / 글로벌 (초록/빨)

`AppSettingsManager` (신규, AppLockManager 패턴 그대로)가 UserDefaults에서 priceColorMode를 읽고 쓴다. ViewModel은 `@State private var settings = AppSettingsManager.shared`로 구독.

---

## 빈 상태와 에러 처리

| 조건 | 화면 |
|---|---|
| 거래소 등록 0개 | 기존 `emptyStateView` ("연결된 거래소가 없습니다") |
| 첫 진입 + 데이터 로딩 중 | 풀스크린 ProgressView |
| 백그라운드 갱신 중 (데이터 있음) | 우측 상단 작은 spinner (DashboardToolbar 안) |
| 모든 거래소 fetch 실패 + assets 빈 상태 | 기존 errorView (재시도 버튼) |
| 일부 거래소만 실패 | 데이터 정상 표시 + ExchangeStatusBanner 노출 |
| 필터 결과 빈 상태 | "선택한 거래소에 보유 자산이 없습니다" |
| Dust 토글로 모두 숨겨진 상태 | "표시할 자산이 없습니다 (dust 숨김 해제)" + 토글 |

---

## 테스트 전략

신규 파일: `CryptoTrackTests/DashboardViewModelTests.swift`

핵심 케이스:

1. **Dust 필터링**
   - `hideDust = true` + ₩999 자산 → displayedRows에서 제외 (단, ticker가 있을 때만)
   - `hideDust = true` + ticker 미수신 자산 → displayedRows에 그대로 포함
   - `hideDust = false` → 포함

2. **통화 분리 합산**
   - Upbit BTC + Bithumb ETH + Binance SOL → krwSummary는 KRW 2개, usdSummary는 USDT 1개

3. **수익률 계산**
   - cost > 0 → `(value - cost) / cost * 100`
   - 모든 자산이 cost=0 → profitRate=0 + `hasUnknownCostBasis=true`
   - 일부만 cost=0 → cost가 있는 것만 합산 + flag

4. **시세 매칭 (regression)**
   - BTC@upbit ticker만 있는데 BTC@binance asset 조회 → `currentValue` = 0
   - 이전 코드의 잘못된 fallback 동작이 다시 들어오지 않음을 보장

5. **필터 + 정렬**
   - `selectedFilter = .exchange(.upbit)` → upbit만 남음
   - `tableSortOrder = [KeyPathComparator(\.currentValue, order: .reverse)]` → 평가금액 내림차순

6. **요약 합산: dust 포함**
   - dust 토글로 시각 숨김된 자산도 krwSummary 합산에 포함되는지 검증

7. **거래소별 fetch 결과 처리**
   - 일부 거래소가 .failure를 반환해도 .success인 거래소의 자산은 newAssets에 포함됨
   - exchangeStatuses에 모든 거래소 entry가 들어옴

---

## 빌드 순서 (스텝 단위)

각 스텝은 빌드 가능한 상태로 끝난다.

| 스텝 | 변경 | 산출물 | 빌드? |
|---|---|---|---|
| 1 | `QuoteCurrency`, `Exchange.quoteCurrency`, `ExchangeFilter` enum 추가 | Models | ✅ |
| 2 | `Asset.hasCostBasis`, `Asset.quoteCurrency` 헬퍼 추가 | Models | ✅ |
| 3 | `AppSettings.priceColorMode` + `AppSettingsManager` (신규, UserDefaults) + `PriceColor` 헬퍼 | Models + Helper | ✅ |
| 4 | `ExchangeManager.fetchAssetsPerExchange` / `fetchTickersPerExchange` 추가 (기존 메서드 유지) | Service | ✅ |
| 5 | `DashboardViewModel` 확장: `AssetRow` 정의, 새 state, computed (`displayedRows`, `krwSummary`, `usdSummary`), 시세 매칭 수정, refresh 거래소별 추적, 자동 갱신 | ViewModel | ✅ (기존 View와 호환) |
| 6 | `DashboardViewModelTests` 작성 + 통과 | Tests | ✅ |
| 7 | `AssetFilterTabBar`, `PortfolioSummaryCard`(개편), `DashboardToolbar`, `ExchangeStatusBanner`, `ProfitBadge`, `PriceFormatter` 컴포넌트 | Views | ✅ |
| 8 | `AssetTable` (macOS) + `AssetRow` 변환 | Views | ✅ macOS만 |
| 9 | `AssetCardList` + `AssetCardRow` (iOS) | Views | ✅ iOS만 |
| 10 | `DashboardView` 컨테이너 재구성 | Views | ✅ 양 플랫폼 |
| 11 | `SettingsView`에 표시 설정 섹션 (색상 모드 Picker) 추가 | Views | ✅ |
| 12 | 양 플랫폼 빌드 + 수동 검증 | — | ✅ |

각 스텝의 핵심: **이전 스텝을 깨지 않는다.** 특히 스텝 5에서 ViewModel을 확장만 하고 기존 `totalValue`/`portfolioList`는 그대로 유지하다가, 스텝 10에서 한 번에 교체.

---

## 보안 / 기술 제약 준수

- API 키는 기존대로 Keychain만 사용. 새 데이터 흐름이 키에 접근하지 않음.
- ViewModel은 ExchangeManager만 의존. ExchangeManager가 KeychainService를 통해서만 키를 읽음.
- AppSettings의 priceColorMode는 UserDefaults에 저장 (CLAUDE.md의 "설정값(테마, 단위 등)은 UserDefaults" 규칙 준수).
- 모든 비동기는 async/await 사용. Completion handler 없음.
- 에러 핸들링: 거래소별 fetch는 do-catch로 감싸고, 사용자에게는 ExchangeStatusBanner로 피드백.
