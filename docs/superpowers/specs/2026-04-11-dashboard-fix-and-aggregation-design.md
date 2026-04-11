# Dashboard Fix & Aggregation Design

- **Date:** 2026-04-11
- **Branch:** `feature/dashboard-revamp`
- **Relates to prior work:** `2026-04-11-dashboard-revamp-design.md` (필터/요약/테이블 재구축) — 본 문서는 그 작업 위에 누락된 버그 수정과 "전체" 탭 집계 UX를 얹는 후속 스펙.

## 배경

최근 재구축된 대시보드(feat: rebuild DashboardView with new filter/summary/table components)에 두 가지 문제가 남아 있다.

### 버그: 거래소별 현재가가 "—"로 표시됨

`DashboardViewModel.refresh()` 는 모든 거래소의 보유 자산 심볼을 `Set` 으로 합친 뒤, 그 합집합을 `ExchangeManager.fetchTickersPerExchange(symbols:)` 로 **모든** 거래소에 동일하게 전달한다. 거래소마다 상장 종목이 다르기 때문에:

- **Binance** — `fetchMultipleTickers(pairs:)` 가 `/api/v3/ticker/24hr?symbols=[...]` 배치 호출을 사용. 한 심볼이라도 상장되지 않았거나 USDT 페어가 없으면 요청 전체가 400으로 실패 → Binance ticker 0개.
- **Upbit** — `KRW-\(symbol)` 를 단일 `markets` 쿼리에 묶어 보냄. 동일한 실패 모드.
- **Bithumb** — 동일 구조.

즉 사용자가 원화 거래소와 해외 거래소를 동시에 연결한 순간, 서로의 심볼 때문에 양쪽 ticker가 동시에 전부 날아갈 수 있다. 대시보드에서 "현재가"와 "평가금액"이 대부분 "—" 또는 0으로 표시되는 증상의 근본 원인이다.

### UX 이슈: 거래소 배지와 미집계 행

- `AssetTable` (macOS) 의 "코인" 컬럼과 `AssetCardList` (iOS) 의 카드 서브 라인은 심볼 옆에 항상 거래소 이름을 capsule/텍스트로 표시한다. 특정 거래소 탭에서는 중복 정보, 전체 탭에서는 행이 거래소마다 따로 나타나 "BTC" 가 여러 줄로 흩어진다.
- `displayedRows` 는 단순 flat list. 동일 심볼을 합산하는 로직이 없다. "전체" 탭에서 "내 BTC 총량"을 한눈에 볼 수 없다.
- 평단가는 각 거래소 단독 값만 보인다. 여러 거래소에 같은 코인을 가진 경우 "전체 평균 매수가"를 계산해 주지 않는다.

## 목표

1. Ticker fetch 버그 수정 — 각 거래소는 자기 보유 심볼의 ticker만 받는다.
2. "전체" 탭에서 동일 코인을 **통화 경계를 넘지 않고** 집계해 한 행으로 보여준다.
3. 합쳐진 행의 평단가를 알려진 cost basis 만으로 weighted average 계산한다.
4. 거래소 배지를 거래소 로고(번들된 에셋) + 브랜드 컬러 모노그램 폴백 하이브리드로 바꾼다. 배지는 집계된 행에만 표시, 특정 거래소 필터에서는 숨긴다.

## 비목표

- FX(KRW↔USDT) 환산. 환율 소스와 캐시 이슈가 별도 설계를 요구하므로, 본 스펙은 "통화별 분리 집계" 를 고수한다. 같은 BTC라도 KRW 거래소 그룹과 USD 거래소 그룹의 BTC는 서로 섞이지 않는다.
- 행을 탭해 거래소별 세부를 펼치는 disclosure UI. 향후 확장 여지로 남김.
- iCloud 동기화 동작 변경.
- 기존 `Services/Exchange/*Service.swift` 개별 구현 변경 (scoping 은 ExchangeManager + ViewModel 수준에서 처리).

## 설계

### 1. 데이터 계층

#### 1-1. Ticker fetch scoping

`ExchangeManager.fetchTickersPerExchange` 의 시그니처를 다음과 같이 교체한다.

```swift
// before
func fetchTickersPerExchange(symbols: [String]) async -> [(Exchange, Result<[Ticker], Error>)]

// after
func fetchTickersPerExchange(
    symbolsByExchange: [Exchange: [String]]
) async -> [(Exchange, Result<[Ticker], Error>)]
```

각 태스크는 `symbolsByExchange[exchange] ?? []` 를 해당 거래소의 `fetchTickers(symbols:)` 에 전달한다. 빈 배열일 경우 fetch 자체를 건너뛰고 `.success([])` 를 돌려준다.

호출부(`DashboardViewModel.refresh`):

```swift
let symbolsByExchange: [Exchange: [String]] = Dictionary(
    grouping: newAssets, by: \.exchange
).mapValues { Array(Set($0.map(\.symbol))) }

let tickerResults = await exchangeManager.fetchTickersPerExchange(
    symbolsByExchange: symbolsByExchange
)
```

기존 `fetchTickersPerExchange(symbols:)` 는 호출처가 `DashboardViewModel` 하나뿐이므로 제거 가능.

#### 1-2. `PortfolioRow` — 표시 행 공통 모델

기존 `AssetRow` 는 단일 Asset 1:1 모델이고 macOS `KeyPathComparator` 와 엮여 flat 필드 구조를 요구한다. 합산 행을 함께 다루기 위해 아래 신규 타입을 도입한다. `AssetRow` 는 제거한다 (참조가 남지 않도록).

```swift
struct PortfolioRow: Identifiable, Sendable {
    let id: String                 // 예: "krw-BTC" / "upbit-BTC" / "usdt-BTC"
    let symbol: String
    let quoteCurrency: QuoteCurrency
    let exchanges: [Exchange]      // 이 행에 포함된 거래소들. Exchange.allCases 순서로 정렬.
    let totalBalance: Double
    let averageBuyPrice: Double    // weighted, known-only. 아무도 모르면 0.
    let currentPrice: Double       // value-weighted: totalValue / totalBalance (>0일 때). 아니면 0.
    let currentValue: Double       // Σ(balance_i × currentPrice_i)
    let profit: Double             // 아래 알고리즘 참조
    let profitRate: Double         // 수익률 %
    let hasCostBasis: Bool         // knownBalance > 0
    let hasPartialCostBasis: Bool  // knownBalance > 0 && knownBalance < totalBalance
    let hasTicker: Bool            // 최소 1개 거래소 ticker 보유
}
```

#### 1-3. `PortfolioAggregator` — 순수 함수 집계

테스트 용이성을 위해 집계 로직은 ViewModel 에서 분리해 순수 함수로 모듈화한다.

```swift
enum PortfolioAggregator {
    /// `.all` 필터용. (symbol, quoteCurrency) 단위로 집계한다.
    static func aggregate(
        assets: [Asset],
        tickers: [Ticker]
    ) -> [PortfolioRow]

    /// `.exchange(_)` 필터용. 단일 거래소 내에서는 (symbol)이 이미 유일하므로
    /// 집계 없이 1:1 변환만 수행한다.
    static func singleExchangeRows(
        assets: [Asset],
        tickers: [Ticker]
    ) -> [PortfolioRow]
}
```

Ticker lookup 은 `(symbol, exchange)` 정확 매치로 수행한다 (기존 `DashboardViewModel.ticker(for:)` 규칙 유지 — 거래소 교차 매칭은 금지).

##### 집계 알고리즘

그룹 키: `(symbol, quoteCurrency)` 튜플. `quoteCurrency` 는 `asset.exchange.quoteCurrency` 로 도출. 같은 그룹에 속한 asset들의 합산을 아래 순서로 계산한다.

```text
totalBalance = Σ balance_i
totalValue   = Σ (balance_i × currentPrice_i)    // ticker 없으면 그 항만 0
knownBalance = Σ balance_i   (hasCostBasis 거래소만)
knownCost    = Σ (balance_i × avgBuyPrice_i)   (hasCostBasis 거래소만)
knownValue   = Σ (balance_i × currentPrice_i)  (hasCostBasis 거래소만, ticker 없으면 0)

averageBuyPrice    = knownBalance > 0 ? knownCost / knownBalance : 0
currentPrice(repr) = totalBalance > 0 ? totalValue / totalBalance : 0
profit             = knownValue - knownCost
profitRate         = knownCost > 0 ? (profit / knownCost) × 100 : 0

hasCostBasis        = knownBalance > 0
hasPartialCostBasis = knownBalance > 0 && knownBalance < totalBalance
hasTicker           = (최소 한 asset에 대해 ticker가 존재)
```

설계 결정:
- **평단가는 "아는 물량의 weighted average"** — 평단을 모르는 물량을 평단가 계산에 끌어들이면 수치가 왜곡된다. 그 물량은 cost basis 합산에서만 제외하고 표시용 totalBalance 에는 포함한다.
- **profit 은 "아는 물량의 손익"** — cost basis 가 없는 물량은 원가를 모르므로 손익 계산에 포함하지 않는다. `hasPartialCostBasis` 배지로 사용자에게 이를 경고한다.
- **currentPrice 는 value-weighted 평균** — 거래소마다 현재가가 다를 수 있으므로 평균 표시 가격은 "평가금액 ÷ 총수량" 으로 역산한다. 이 값은 단일 실시간 가격이 아니라 "내 물량 평균적으로 보는 가격" 이다.
- **통화 경계 절대 금지** — Upbit BTC 와 Binance BTC 는 같은 "전체" 탭에 있어도 별개 행 (KRW 섹션의 BTC, USDT 섹션의 BTC 두 개).

#### 1-4. `DashboardViewModel` 수정

```swift
// 제거
var displayedRows: [AssetRow]
var tableSortOrder: [KeyPathComparator<AssetRow>]

// 신규
struct RowSection: Identifiable, Sendable {
    var id: QuoteCurrency
    var rows: [PortfolioRow]
}

var displayedSections: [RowSection] { ... }

// 정렬 상태 — 섹션별 분리. iOS 에서는 기본값만 사용 (기존 `tableSortOrder` 동작 계승).
var krwSortOrder: [KeyPathComparator<PortfolioRow>] = [
    KeyPathComparator(\PortfolioRow.currentValue, order: .reverse)
]
var usdSortOrder: [KeyPathComparator<PortfolioRow>] = [
    KeyPathComparator(\PortfolioRow.currentValue, order: .reverse)
]
```

`displayedSections` 계산:

1. `selectedFilter == .all` → `PortfolioAggregator.aggregate(assets:tickers:)` 결과를 `quoteCurrency` 로 그룹핑. 각 섹션은 `currentValue` 내림차순 정렬 (iOS) 또는 섹션별 sortOrder 적용 (macOS).
2. `selectedFilter == .exchange(ex)` → 해당 거래소 자산만 필터링 후 `PortfolioAggregator.singleExchangeRows`. 단일 섹션 (해당 거래소의 통화).
3. `hideDust` 필터는 **집계 후** 적용. `currentValue` < threshold (KRW ₩1,000 / USDT $1) 이고 `hasTicker == true` 일 때만 dust 로 간주해 숨긴다. ticker 가 없어 평가가 불가한 행은 숨기지 않는다 (기존 규칙 계승).

### 2. UI 계층

#### 2-1. `ExchangeBadge` / `ExchangeBadgeRow` — 신규 컴포넌트

위치: `CryptoTrack/Views/Dashboard/Components/ExchangeBadge.swift`

```swift
/// 단일 거래소를 나타내는 원형 배지. 로고 에셋이 번들에 있으면 이미지를,
/// 없으면 brandColor + monogram 서클로 폴백한다.
struct ExchangeBadge: View {
    let exchange: Exchange
    var size: CGFloat = 18
    var body: some View { ... }
}

/// 여러 거래소를 가로 배열. Exchange.allCases 순서로 정렬해 렌더링.
/// maxVisible 초과분은 "+N" 으로 축약.
struct ExchangeBadgeRow: View {
    let exchanges: [Exchange]
    var size: CGFloat = 16
    var maxVisible: Int = 4
    var body: some View { ... }
}
```

로고 파일 유무 감지는 `PlatformImage(named:)` 또는 SwiftUI `Image(_)` + `Bundle.main.path` 확인 중 **한 가지를 구현 시점에 선택** — SwiftUI `Image` 는 누락된 에셋을 silently 무시하므로 ZStack에 대체 뷰를 항상 두고 이미지 위에 올리는 방법이 가장 안전하다. 구현 체크리스트:
- `UIImage(named:)` / `NSImage(named:)` 반환 nil 일 때 모노그램 뷰 렌더.
- 다크모드 대응은 이미지 에셋의 appearance variant 또는 `.colorInvert()` 를 사용하지 않고, 동일 이미지를 양쪽에 표시.

#### 2-2. `Exchange+Brand` — 신규 확장

위치: `CryptoTrack/DesignSystem/Exchange+Brand.swift`

```swift
extension Exchange {
    /// 이 거래소의 대표 브랜드 컬러. 모노그램 폴백 배지 배경과 악센트에 사용.
    var brandColor: Color { ... }

    /// 모노그램 폴백 시 표시할 1~2글자 약어.
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

    /// 번들 로고 에셋 이름. imageset 이 누락되면 ExchangeBadge 가 자동으로 모노그램으로 폴백.
    var logoAssetName: String { "logo.\(rawValue.lowercased())" }
}
```

brandColor 는 각 거래소 공식 브랜드 컬러 근사치를 우선 사용. 구현 시 스크린샷과 대조해 미세 조정.

#### 2-3. `AssetTable` (macOS) — `PortfolioRow` + 섹션 두 개 스택

기존 `CryptoTrack/Views/Dashboard/AssetTable.swift` 파일을 유지하되, `AssetTable` 타입을 **`AssetTableSections`** 로 개명하고 내부를 섹션 두 개 스택 구조로 재작성한다. (Table 컬럼 정의 자체는 대부분 재사용 가능해서 파일 이동 없이 개명.)

SwiftUI `Table` 은 섹션을 지원하지 않으므로, "전체" 탭에서는 Table 두 개를 VStack으로 스택한다. `.exchange` 필터 시에는 단일 Table 렌더.

```swift
struct AssetTableSections: View {
    let sections: [RowSection]
    @Binding var krwSortOrder: [KeyPathComparator<PortfolioRow>]
    @Binding var usdSortOrder: [KeyPathComparator<PortfolioRow>]
    let showHeaders: Bool
    let colorMode: PriceColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sections) { section in
                if showHeaders {
                    Text(section.id.sectionTitle)  // "원화 거래소 (KRW)" / "해외 거래소 (USD)"
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                Table(section.rows, sortOrder: binding(for: section.id)) {
                    TableColumn("코인") { row in
                        HStack(spacing: 8) {
                            Text(row.symbol).font(.body.weight(.semibold))
                            if showHeaders {  // .all 이어서 집계된 뷰일 때만 배지 표시
                                ExchangeBadgeRow(exchanges: row.exchanges, size: 16)
                            }
                        }
                    }
                    // balance / averageBuyPrice / currentPrice / currentValue / profitRate 컬럼 (기존과 동일)
                }
            }
        }
    }
}
```

`QuoteCurrency.sectionTitle` 은 표시용 한국어 레이블 — `"원화 거래소 (KRW)"` / `"해외 거래소 (USD)"`. 이 확장은 `CryptoTrack/Models/QuoteCurrency.swift` 에 computed property 로 추가한다 (`displayName` 과 같은 파일).

`binding(for:)` 은 `section.id` 에 따라 `krwSortOrder` 또는 `usdSortOrder` 바인딩을 반환한다. 각 섹션이 독립적으로 정렬되도록.

"—" 표시 규칙은 기존 `AssetTable` 과 동일:
- `hasCostBasis == false` → 평단/수익률 `"—"`
- `hasTicker == false` → 현재가 `"—"`, 평가금액은 0 (`currentValue` 그대로 포맷)

#### 2-4. `AssetCardList` (iOS) — List + Section, 배지 로고 헤더

```swift
struct AssetCardList: View {
    let sections: [RowSection]
    let showSectionHeaders: Bool
    let colorMode: PriceColorMode

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        AssetCardRow(row: row, showBadges: showSectionHeaders, colorMode: colorMode)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    if showSectionHeaders {
                        Text(section.id.sectionTitle).font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
```

카드 행 레이아웃:

```
┌────────────────────────────────────────────────────┐
│ BTC  [🟦][🟧][🟥]+1            ₩75,230,000         │
│ 0.612 BTC                         +12.34% ▲        │
│ ─────                                              │
│ 평단 ₩58,400,000  현재가 ₩122,920,000  [일부 미제공]│
└────────────────────────────────────────────────────┘
```

- 심볼 옆에 `ExchangeBadgeRow` — `showBadges == true` (즉 `.all` 탭) 일 때만.
- 기존의 "Upbit · 0.612 BTC" 형식 서브 라인은 **제거**. 대신 "0.612 BTC" 만 남긴다 (거래소 이름은 배지로 이미 식별 가능하므로 텍스트 중복 금지).
- "3개 거래소" 같은 텍스트 카운트도 넣지 않음 (배지 개수가 곧 카운트).
- `hasPartialCostBasis == true` 일 때만 작은 배지 "일부 미제공" 표시 (기존 PortfolioSummaryCard 패턴과 일관).

#### 2-5. `DashboardView` 수정

`mainContent` 의 `assetsList` 부분:

```swift
@ViewBuilder
private var assetsList: some View {
    if viewModel.displayedSections.isEmpty || viewModel.displayedSections.allSatisfy(\.rows.isEmpty) {
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

`hasOnlyDust` 계산은 `displayedSections.rows` 기반으로 업데이트.

### 3. 로고 에셋

#### 3-1. 카탈로그 구조

`CryptoTrack/Assets.xcassets/` 를 신규 생성. XcodeGen 의 `sources: CryptoTrack` 설정 덕분에 추가 project.yml 수정 없이 다음 `xcodegen` 실행 시 자동 포함된다.

```
CryptoTrack/Assets.xcassets/
├── Contents.json              // {"info":{"version":1,"author":"xcode"}}
└── Logo/
    ├── Contents.json          // 빈 그룹
    ├── upbit.imageset/
    │   ├── Contents.json
    │   └── upbit.svg          // 또는 upbit.png
    ├── binance.imageset/
    ├── bithumb.imageset/
    ├── bybit.imageset/
    ├── coinone.imageset/
    ├── korbit.imageset/
    └── okx.imageset/
```

각 imageset 의 `Contents.json` (SVG 단일 스케일 기준):

```json
{
  "images": [{"filename": "upbit.svg", "idiom": "universal"}],
  "info": {"version": 1, "author": "xcode"},
  "properties": {"preserves-vector-representation": true}
}
```

#### 3-2. 다운로드 소스 우선순위

| Exchange | 1순위 | 2순위 | 폴백 |
|---|---|---|---|
| Upbit    | Wikimedia Commons SVG | 공식 사이트 헤더 로고 | 모노그램 |
| Binance  | Wikimedia Commons SVG | binance.com brand kit | 모노그램 |
| Bithumb  | Wikimedia Commons SVG | 공식 사이트 | 모노그램 |
| Bybit    | bybit.com brand kit    | Wikimedia Commons    | 모노그램 |
| Coinone  | Wikimedia Commons SVG | 공식 사이트 | 모노그램 |
| Korbit   | Wikimedia Commons SVG | 공식 사이트 | 모노그램 |
| OKX      | okx.com brand kit      | Wikimedia Commons    | 모노그램 |

#### 3-3. 다운로드 후 검증

- 파일 크기 ≥ 100바이트 (빈 응답 방어).
- 매직넘버 확인 — SVG 는 `"<svg"` 또는 `"<?xml"` 포함, PNG 는 `89 50 4E 47` 시작.
- SwiftUI 프리뷰에서 모든 로고가 정상 렌더되는지 시각 확인.
- 어느 거래소라도 실패/이상 시 해당 imageset 폴더를 삭제 → `ExchangeBadge` 자동 모노그램 폴백.

#### 3-4. 상표 사용 정책 (README 추가 문구)

```
Exchange logos shown in this app are trademarks of their respective owners
and are used solely to identify which exchange a given asset resides in
(nominative fair use). Removal is supported by deleting the corresponding
imageset under Assets.xcassets/Logo/.
```

### 4. 테스트 전략

#### 4-1. `PortfolioAggregatorTests.swift` — 단위 테스트

순수 함수이므로 Service mock 없이 `[Asset]` + `[Ticker]` 를 입력해 결과를 assert 한다.

1. **KRW 단일 섹션 — 모든 평단 알려짐**
   - Input: Upbit BTC 0.5@55M + Bithumb BTC 0.3@60M + tickers 62M (양쪽)
   - Expect: 1행, totalBalance 0.8, averageBuyPrice ≈ 56.875M, currentValue 49.6M, profit 4.1M, profitRate ≈ 9.0%, hasCostBasis, `!hasPartialCostBasis`, exchanges == [.upbit, .bithumb]

2. **Partial cost basis**
   - Input: Upbit BTC 0.5@55M + Bithumb BTC 0.3@0 + tickers 62M (양쪽)
   - Expect: averageBuyPrice 55M, profit 은 Upbit 0.5 물량만 기준, hasPartialCostBasis == true

3. **해외 섹션 (cost basis 전무)**
   - Input: Binance BTC 0.2 + OKX BTC 0.1, 평단 0, tickers 47500 (양쪽)
   - Expect: averageBuyPrice 0, currentValue 14250, profit 0, profitRate 0, hasCostBasis == false

4. **Mixed currency — 동일 심볼 분리**
   - Input: Upbit BTC 0.5@55M + Binance BTC 0.2@0
   - Expect: KRW 섹션 BTC 1행(balance 0.5) + USDT 섹션 BTC 1행(balance 0.2). 두 행이 절대 합쳐지지 않음

5. **Ticker 누락 거래소 holder**
   - Input: Upbit BTC 0.5 + Bithumb BTC 0.3, Bithumb ticker 없음
   - Expect: currentValue = 0.5 × upbitPrice (Bithumb 분 0 취급). hasTicker == true (Upbit 보유). 행은 정상 표시.

6. **단일 거래소 필터 — `singleExchangeRows`**
   - Input: Upbit BTC + Upbit ETH + Upbit XRP (평단 다 있음)
   - Expect: 3행, 각 행의 exchanges == [.upbit], 집계 없음

7. **Dust filter 경계 (ViewModel 단위 테스트)**
   - Input: Upbit BTC ₩500 + Bithumb BTC ₩500 + Coinone BTC ₩500 + Korbit BTC ₩500 (합 ₩2000)
   - Expect: `hideDust == true` 에서도 합쳐진 행은 표시됨 (threshold 초과)

#### 4-2. ViewModel 통합 테스트

기존 DashboardViewModel 테스트가 `displayedRows` / `tableSortOrder` 를 참조하고 있으면, `displayedSections` / 섹션별 sortOrder 로 갱신한다. 기존 테스트 파일 존재 여부는 구현 1단계 착수 시점에 `CryptoTrackTests` 하위를 확인.

#### 4-3. 수동 회귀 시나리오

iOS / macOS 각각:

1. Upbit 단독 → "전체" 탭 = Upbit 탭과 동일 (섹션 하나, 배지 없음).
2. Binance 단독 → USD 섹션만, 평단 전부 "—".
3. Upbit + Binance 동시 → 전체 탭에 섹션 2개. 이전 버그: 양쪽 ticker 전부 "—". 수정 후: 양쪽 현재가 정상 표시.
4. 같은 코인이 Upbit+Bithumb 에 있을 때 → KRW 섹션 BTC 1행으로 합쳐짐. 평단이 weighted average.
5. 필터 탭을 Upbit 으로 전환 → 섹션 헤더 사라짐, 배지 사라짐, BTC 는 합산 없이 Upbit 값만.
6. 소액 숨김 토글 → dust 기준이 합산 후 적용되는지.
7. macOS 컬럼 클릭 정렬 → 섹션별 독립 정렬 동작.

### 5. 빌드 시퀀스

각 단계 끝은 빌드 + 핵심 기능 동작 체크포인트.

**1단계 — 데이터 계층 + 버그 픽스**
- `PortfolioRow.swift` 추가
- `PortfolioAggregator.swift` 추가
- `ExchangeManager.fetchTickersPerExchange(symbolsByExchange:)` 교체
- `DashboardViewModel.refresh()` symbol scoping 적용
- `PortfolioAggregatorTests.swift` 작성 & 통과
- 체크포인트: ticker 버그 자체는 이 단계에서 수정됨. 기존 flat UI 로도 동작 확인.

**2단계 — UI 재구조화**
- `DashboardViewModel` 에 `displayedSections`, 섹션별 정렬 상태 도입. `displayedRows` / `tableSortOrder` / `AssetRow` 제거.
- `AssetTable` → `AssetTableSections` 로 교체 (섹션 두 개 스택 구조).
- `AssetCardList` → List + Section 구조로 교체.
- `DashboardView` 가 sections/showSectionHeaders 를 넘기도록 수정.
- 체크포인트: `.all` 에서 두 섹션 표시, 합산 수치 육안 검증, `.exchange` 탭 단일 섹션.

**3단계 — 배지 컴포넌트 (모노그램 only)**
- `Exchange+Brand.swift` 추가
- `ExchangeBadge` / `ExchangeBadgeRow` 추가
- macOS Table 코인 컬럼 / iOS 카드 헤더에 배지 통합 (`.all` 일 때만)
- 체크포인트: 모든 거래소가 모노그램 서클로 표시, 배지 개수/순서 맞음.

**4단계 — 로고 에셋 다운로드**
- `Assets.xcassets/Logo/*.imageset/` 7개 생성 + SVG/PNG 다운로드
- `xcodegen` 재실행 → Xcode 프로젝트 갱신
- SwiftUI Preview 로 각 거래소 로고 렌더 확인
- 체크포인트: 로고 성공 거래소는 이미지, 실패 거래소는 모노그램으로 자동 혼재. README 상표 주석 추가.

**5단계 — 검증 & 마무리**
- `superpowers:verification-before-completion` 스킬로 iOS / macOS 각각 빌드 + 수동 시나리오 7개 체크
- 기존 테스트 수트 그린 확인
- `finishing-a-development-branch` 로 `develop` 머지 경로 결정

## 리스크 & 오픈 질문

1. **로고 다운로드 소스 접근성** — Wikimedia Commons 파일 URL 이 모든 7개 거래소에 대해 안정적으로 존재하는지는 실제 다운로드 시점에 확인 가능. 실패 시 모노그램 폴백으로 UI 깨지지 않음 보장.
2. **macOS Table 섹션별 정렬 — 컬럼 폭 정렬** — 두 Table 이 독립적으로 자동 컬럼 폭을 계산해 시각적으로 어긋날 수 있음. 구현 시 모든 컬럼에 명시적 `width(min:ideal:)` 지정으로 해결.
3. **FX 미지원** — 원화 거래소와 해외 거래소를 동시에 쓰는 사용자는 "전체 포트폴리오 합계" 를 한 수치로 볼 수 없음. PortfolioSummaryCard 가 KRW/USD 두 줄로 나뉘어 있는 기존 구조 계승. 향후 환율 연동은 별도 스펙.
4. **기존 `AssetRow` 참조 전수 제거** — 구현 시 컴파일러가 알려줄 것이고, 그 외 숨은 참조는 없다고 판단. 테스트 파일까지 확인 필요.
