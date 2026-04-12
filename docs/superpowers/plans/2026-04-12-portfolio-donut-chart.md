# 보유 비중 도넛 차트 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 대시보드 `PortfolioSummaryCard` 안에 통화 그룹별 자산 보유 비중 도넛 차트를 추가한다.

**Architecture:** SwiftUI Shape 기반 커스텀 도넛 차트를 `DonutChartView.swift`에 구현하고, 기존 `PortfolioSummaryCard`의 `SummaryBlock`에 통합한다. iOS에서는 접기/펼치기 토글을 제공하고(`@AppStorage` 영속), macOS에서는 요약 좌측 + 차트 우측 가로 레이아웃으로 항상 표시한다.

**Tech Stack:** SwiftUI (Shape, Canvas 없이 Path 기반), `@AppStorage`

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `CryptoTrack/Views/Dashboard/Components/DonutChartView.swift` | 도넛 Shape, 범례, 조합 뷰 |
| Modify | `CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift` | SummaryBlock에 도넛 차트 삽입, 플랫폼별 레이아웃 |
| Modify | `CryptoTrack/ViewModels/DashboardViewModel.swift` | 비중 데이터 계산 computed property 추가 |
| Create | `CryptoTrackTests/DonutChartDataTests.swift` | 비중 계산 로직 테스트 |

---

### Task 1: 비중 계산 로직 — 테스트 작성

**Files:**
- Create: `CryptoTrackTests/DonutChartDataTests.swift`

- [ ] **Step 1: 비중 데이터 모델 및 계산 로직 테스트 작성**

```swift
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
        // ETH has currentValue 0, but hideDust is false so it shows up
        // However 0-value rows contribute 0% — they should be excluded from chart
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].symbol, "BTC")
        XCTAssertEqual(slices[0].percentage, 100.0, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: 테스트 실행 — 컴파일 에러 확인**

Run: `xcodebuild test -scheme CryptoTrack -destination 'platform=macOS' -only-testing:CryptoTrackTests/DonutChartDataTests 2>&1 | tail -20`
Expected: 컴파일 에러 — `allocationSlices(for:)` 메서드, `AllocationSlice` 타입 미존재

- [ ] **Step 3: Commit**

```bash
git add CryptoTrackTests/DonutChartDataTests.swift
git commit -m "test: add DonutChartDataTests for allocation slice calculation"
```

---

### Task 2: 비중 계산 로직 — 구현

**Files:**
- Modify: `CryptoTrack/ViewModels/DashboardViewModel.swift`

- [ ] **Step 1: AllocationSlice 모델 및 계산 로직 추가**

`DashboardViewModel.swift` 파일 상단 (struct 정의 영역, `RowSection` 아래)에 모델 추가:

```swift
/// 도넛 차트의 한 조각 — 코인 심볼과 비중(%).
struct AllocationSlice: Identifiable, Sendable {
    var id: String { symbol }
    let symbol: String
    let percentage: Double
    let value: Double
}
```

`DashboardViewModel` 클래스 내부 (`displayedSections` 근처)에 메서드 추가:

```swift
// MARK: - Allocation Slices (donut chart)

/// 지정 통화 그룹의 비중 데이터를 반환한다.
/// `displayedSections`의 dust 필터 및 거래소 필터가 반영된 행을 기준으로 계산.
/// currentValue가 0인 행은 제외한다.
func allocationSlices(for currency: QuoteCurrency) -> [AllocationSlice] {
    let rows = displayedSections
        .first { $0.id == currency }?
        .rows ?? []

    let nonZeroRows = rows.filter { $0.currentValue > 0 }
    let total = nonZeroRows.reduce(0.0) { $0 + $1.currentValue }
    guard total > 0 else { return [] }

    return nonZeroRows
        .sorted { $0.currentValue > $1.currentValue }
        .map { row in
            AllocationSlice(
                symbol: row.symbol,
                percentage: (row.currentValue / total) * 100,
                value: row.currentValue
            )
        }
}
```

- [ ] **Step 2: 테스트 실행 — 전부 통과 확인**

Run: `xcodebuild test -scheme CryptoTrack -destination 'platform=macOS' -only-testing:CryptoTrackTests/DonutChartDataTests 2>&1 | tail -20`
Expected: 7 tests PASS

- [ ] **Step 3: 기존 테스트 회귀 확인**

Run: `xcodebuild test -scheme CryptoTrack -destination 'platform=macOS' -only-testing:CryptoTrackTests/DashboardViewModelTests 2>&1 | tail -10`
Expected: 기존 테스트 전부 PASS

- [ ] **Step 4: Commit**

```bash
git add CryptoTrack/ViewModels/DashboardViewModel.swift
git commit -m "feat: add allocationSlices computed property for donut chart data"
```

---

### Task 3: DonutChartView 컴포넌트 구현

**Files:**
- Create: `CryptoTrack/Views/Dashboard/Components/DonutChartView.swift`

- [ ] **Step 1: DonutChartView 전체 구현**

```swift
// CryptoTrack/Views/Dashboard/Components/DonutChartView.swift
import SwiftUI

/// 도넛 차트의 색상 팔레트.
private let donutColors: [Color] = [
    .green, .blue, .orange, .pink, .cyan,
    .purple, .yellow, .mint, .indigo, .teal,
    .brown, .red,
]

/// 도넛 차트 한 조각을 그리는 Shape.
private struct DonutSegment: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * 0.6

        var path = Path()
        path.addArc(
            center: center, radius: radius,
            startAngle: startAngle, endAngle: endAngle, clockwise: false
        )
        path.addArc(
            center: center, radius: innerRadius,
            startAngle: endAngle, endAngle: startAngle, clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

/// 도넛 차트 + 중앙 텍스트.
struct DonutChart: View {
    let slices: [AllocationSlice]
    let size: CGFloat

    var body: some View {
        ZStack {
            if slices.isEmpty {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: size * 0.2)
                    .frame(width: size, height: size)
            } else {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    DonutSegment(
                        startAngle: segment.start,
                        endAngle: segment.end
                    )
                    .fill(donutColors[index % donutColors.count])
                }
                .frame(width: size, height: size)
            }

            // 중앙 텍스트
            VStack(spacing: 2) {
                Text("비중")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(slices.count)종")
                    .font(.subheadline.weight(.bold))
            }
        }
        .frame(width: size, height: size)
    }

    /// 각 슬라이스의 시작/끝 각도를 계산한다.
    /// 12시 방향(-90°)부터 시계 방향으로 그린다.
    private var segments: [(start: Angle, end: Angle)] {
        var result: [(Angle, Angle)] = []
        // gap: 슬라이스 간 1° 간격
        let gapDegrees: Double = slices.count > 1 ? 1.0 : 0
        let totalGap = gapDegrees * Double(slices.count)
        let available = 360.0 - totalGap
        var current: Double = -90

        for slice in slices {
            let span = available * (slice.percentage / 100.0)
            let start = Angle.degrees(current)
            let end = Angle.degrees(current + span)
            result.append((start, end))
            current += span + gapDegrees
        }
        return result
    }
}

/// 범례 리스트.
struct DonutLegend: View {
    let slices: [AllocationSlice]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                HStack(spacing: 8) {
                    Circle()
                        .fill(donutColors[index % donutColors.count])
                        .frame(width: 8, height: 8)
                    Text(slice.symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(width: 40, alignment: .leading)
                    Spacer()
                    Text(String(format: "%.1f%%", slice.percentage))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
    }
}

/// 도넛 차트 + 범례를 가로로 배치하는 조합 뷰.
struct DonutChartView: View {
    let slices: [AllocationSlice]
    var chartSize: CGFloat = 120

    var body: some View {
        HStack(spacing: 16) {
            DonutChart(slices: slices, size: chartSize)
            DonutLegend(slices: slices)
        }
    }
}

// MARK: - Preview

#Preview("donut chart") {
    DonutChartView(
        slices: [
            AllocationSlice(symbol: "BTC", percentage: 36.2, value: 31_000_000),
            AllocationSlice(symbol: "ETH", percentage: 25.5, value: 9_920_000),
            AllocationSlice(symbol: "XRP", percentage: 18.3, value: 984_000),
            AllocationSlice(symbol: "SOL", percentage: 12.1, value: 2_475_000),
            AllocationSlice(symbol: "ADA", percentage: 7.9, value: 3_100_000),
        ]
    )
    .padding()
    .background(.background.secondary)
    .preferredColorScheme(.dark)
}

#Preview("single asset") {
    DonutChartView(
        slices: [
            AllocationSlice(symbol: "BTC", percentage: 100, value: 31_000_000),
        ]
    )
    .padding()
    .background(.background.secondary)
    .preferredColorScheme(.dark)
}

#Preview("empty") {
    DonutChartView(slices: [])
        .padding()
        .background(.background.secondary)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Xcode 프로젝트에 파일 추가 확인 및 빌드**

Run: `xcodebuild build -scheme CryptoTrack -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Views/Dashboard/Components/DonutChartView.swift
git commit -m "feat: add DonutChartView component with donut shape and legend"
```

---

### Task 4: PortfolioSummaryCard에 도넛 차트 통합

**Files:**
- Modify: `CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift`

- [ ] **Step 1: PortfolioSummaryCard에 slices 파라미터 추가**

`PortfolioSummaryCard`에 통화별 슬라이스 데이터와 접기 상태를 추가한다.

`PortfolioSummaryCard.swift`의 기존 프로퍼티:

```swift
struct PortfolioSummaryCard: View {
    let krw: CurrencySummary?
    let usd: CurrencySummary?
    let colorMode: PriceColorMode
```

아래로 변경:

```swift
struct PortfolioSummaryCard: View {
    let krw: CurrencySummary?
    let usd: CurrencySummary?
    let colorMode: PriceColorMode
    var krwSlices: [AllocationSlice] = []
    var usdSlices: [AllocationSlice] = []

    @AppStorage("donutChartExpanded") private var isChartExpanded: Bool = true
```

- [ ] **Step 2: SummaryBlock에 도넛 차트 섹션 추가**

`SummaryBlock`에 slices 파라미터를 추가하고, 플랫폼별 레이아웃을 구현한다.

기존 `SummaryBlock`:

```swift
private struct SummaryBlock: View {
    let summary: CurrencySummary
    let colorMode: PriceColorMode
```

아래로 변경:

```swift
private struct SummaryBlock: View {
    let summary: CurrencySummary
    let colorMode: PriceColorMode
    let slices: [AllocationSlice]
    @Binding var isChartExpanded: Bool
```

`SummaryBlock`의 `body`를 플랫폼별로 분기한다:

```swift
    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS: 가로 배치 (접기 없음)

    private var macOSLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            summaryContent
            if !slices.isEmpty {
                Divider()
                    .frame(height: 120)
                DonutChartView(slices: slices, chartSize: 100)
            }
        }
    }

    // MARK: - iOS: 세로 배치 + 접기/펼치기

    private var iOSLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryContent

            if !slices.isEmpty {
                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isChartExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("보유 비중")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isChartExpanded ? 0 : -90))
                    }
                }
                .buttonStyle(.plain)

                if isChartExpanded {
                    DonutChartView(slices: slices)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - 요약 정보 (공통)

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.currency.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(PriceFormatter.formatRate(summary.profitRate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PriceColor.color(for: summary.profitRate, mode: colorMode))
                    .monospacedDigit()
            }

            valueRow(label: "총 매수", value: PriceFormatter.formatAmount(summary.totalCost, currency: summary.currency))
            valueRow(label: "총 평가", value: PriceFormatter.formatAmount(summary.totalValue, currency: summary.currency), emphasized: true)
            valueRow(
                label: "수익",
                value: PriceFormatter.formatSignedAmount(summary.totalProfit, currency: summary.currency),
                tint: PriceColor.color(for: summary.totalProfit, mode: colorMode)
            )

            if summary.hasUnknownCostBasis {
                Text("일부 자산 평단가 미제공")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
```

- [ ] **Step 3: PortfolioSummaryCard body에서 SummaryBlock에 slices 전달**

기존 body:

```swift
    var body: some View {
        VStack(spacing: 12) {
            if let krw {
                SummaryBlock(summary: krw, colorMode: colorMode)
            }
            if krw != nil && usd != nil {
                Divider()
            }
            if let usd {
                SummaryBlock(summary: usd, colorMode: colorMode)
            }
        }
```

아래로 변경:

```swift
    var body: some View {
        VStack(spacing: 12) {
            if let krw {
                SummaryBlock(
                    summary: krw, colorMode: colorMode,
                    slices: krwSlices, isChartExpanded: $isChartExpanded
                )
            }
            if krw != nil && usd != nil {
                Divider()
            }
            if let usd {
                SummaryBlock(
                    summary: usd, colorMode: colorMode,
                    slices: usdSlices, isChartExpanded: $isChartExpanded
                )
            }
        }
```

- [ ] **Step 4: Preview 업데이트**

기존 Preview를 업데이트:

```swift
#Preview {
    PortfolioSummaryCard(
        krw: CurrencySummary(
            currency: .krw,
            totalValue: 12_847_300,
            totalCost: 11_600_000,
            totalProfit: 1_247_300,
            profitRate: 10.74,
            hasUnknownCostBasis: false
        ),
        usd: CurrencySummary(
            currency: .usdt,
            totalValue: 3_247.50,
            totalCost: 0,
            totalProfit: 0,
            profitRate: 0,
            hasUnknownCostBasis: true
        ),
        colorMode: .korean,
        krwSlices: [
            AllocationSlice(symbol: "BTC", percentage: 60.0, value: 7_708_380),
            AllocationSlice(symbol: "ETH", percentage: 25.0, value: 3_211_825),
            AllocationSlice(symbol: "XRP", percentage: 15.0, value: 1_927_095),
        ],
        usdSlices: [
            AllocationSlice(symbol: "SOL", percentage: 55.0, value: 1_786),
            AllocationSlice(symbol: "AVAX", percentage: 45.0, value: 1_461),
        ]
    )
    .padding()
}
```

- [ ] **Step 5: 빌드 확인**

Run: `xcodebuild build -scheme CryptoTrack -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift
git commit -m "feat: integrate donut chart into PortfolioSummaryCard with platform-specific layout"
```

---

### Task 5: DashboardView에서 slices 전달

**Files:**
- Modify: `CryptoTrack/Views/Dashboard/DashboardView.swift`

- [ ] **Step 1: PortfolioSummaryCard 호출부에 slices 추가**

`DashboardView.swift`의 `mainContent`에서 `PortfolioSummaryCard` 호출을 수정한다.

기존:

```swift
            PortfolioSummaryCard(
                krw: viewModel.krwSummary,
                usd: viewModel.usdSummary,
                colorMode: settingsManager.priceColorMode
            )
```

아래로 변경:

```swift
            PortfolioSummaryCard(
                krw: viewModel.krwSummary,
                usd: viewModel.usdSummary,
                colorMode: settingsManager.priceColorMode,
                krwSlices: viewModel.allocationSlices(for: .krw),
                usdSlices: viewModel.allocationSlices(for: .usdt)
            )
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild build -scheme CryptoTrack -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 전체 테스트 실행**

Run: `xcodebuild test -scheme CryptoTrack -destination 'platform=macOS' 2>&1 | tail -20`
Expected: 모든 테스트 PASS

- [ ] **Step 4: Commit**

```bash
git add CryptoTrack/Views/Dashboard/DashboardView.swift
git commit -m "feat: pass allocation slices from DashboardView to PortfolioSummaryCard"
```

---

### Task 6: UI 검증 및 엣지 케이스 확인

- [ ] **Step 1: macOS에서 앱 실행 및 시각 확인**

Run: `xcodebuild build -scheme CryptoTrack -destination 'platform=macOS' && open -a CryptoTrack`

확인 사항:
- 요약 카드 왼쪽에 금액, 오른쪽에 도넛 차트가 가로 배치되는지
- KRW/USD 각각 독립 차트가 표시되는지
- 범례 퍼센트 합이 100%에 근접하는지
- 코인 1개일 때 완전 원형 도넛이 되는지
- 자산 0개(거래소 미등록)일 때 차트가 안 보이는지

- [ ] **Step 2: Preview로 iOS 레이아웃 확인**

Xcode에서 `PortfolioSummaryCard` Preview를 열어 확인:
- 접기/펼치기 토글 동작
- 셰브론 회전 애니메이션
- 접었다 펼 때 부드러운 전환

- [ ] **Step 3: Commit (필요 시 수정사항)**

```bash
git add -A
git commit -m "fix: polish donut chart layout and edge cases"
```
