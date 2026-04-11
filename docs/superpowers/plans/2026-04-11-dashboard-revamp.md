# Dashboard Revamp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 거래소 통합 대시보드의 시세 매칭 버그를 수정하고, 거래소 필터 탭 + KRW/USD 통화 분리 요약 + 코인별 상세 테이블(macOS) / 카드 리스트(iOS)를 추가한다.

**Architecture:** ExchangeManager·Service 계층은 그대로 두고, DashboardViewModel을 확장(필터/정렬/요약 computed property + 거래소별 fetch 결과 추적 + 자동 갱신 루프)하여 표시 로직을 모두 흡수한다. 새 View 컴포넌트들은 `Views/Dashboard/`에 모듈화하고, 플랫폼 분기는 `#if os(macOS)`로 처리한다.

**Tech Stack:** Swift 6, SwiftUI (iOS 17+, macOS 14+), `@Observable`, async/await, XCTest, xcodegen.

**Spec:** `docs/superpowers/specs/2026-04-11-dashboard-revamp-design.md`

---

## File Structure

**Created:**
- `CryptoTrack/Models/QuoteCurrency.swift` — 통화 enum + Exchange.quoteCurrency 확장
- `CryptoTrack/Models/ExchangeFilter.swift` — 탭 필터 enum
- `CryptoTrack/Models/PriceColorMode.swift` — 색상 모드 enum
- `CryptoTrack/ViewModels/AssetRow.swift` — Table/CardList 표시용 평탄화 행 모델
- `CryptoTrack/Services/Settings/AppSettingsManager.swift` — UserDefaults 기반 설정 매니저
- `CryptoTrack/Views/Dashboard/Components/PriceColor.swift` — 색상 모드 헬퍼
- `CryptoTrack/Views/Dashboard/Components/PriceFormatter.swift` — 통화별 숫자 포맷
- `CryptoTrack/Views/Dashboard/Components/ProfitBadge.swift` — 수익률 표시 칩
- `CryptoTrack/Views/Dashboard/AssetFilterTabBar.swift` — 거래소 필터 탭바
- `CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift` — KRW/USD 두 줄 요약 카드
- `CryptoTrack/Views/Dashboard/DashboardToolbar.swift` — dust 토글 + 새로고침 + 갱신 시각
- `CryptoTrack/Views/Dashboard/ExchangeStatusBanner.swift` — 일부 fetch 실패 알림
- `CryptoTrack/Views/Dashboard/AssetTable.swift` — macOS 전용 SwiftUI Table
- `CryptoTrack/Views/Dashboard/AssetCardList.swift` — iOS 전용 카드형 리스트
- `CryptoTrackTests/DashboardViewModelTests.swift` — 신규 ViewModel 테스트

**Modified:**
- `CryptoTrack/Models/Asset.swift` — `hasCostBasis`, `quoteCurrency` 헬퍼 추가
- `CryptoTrack/Models/AppSettings.swift` — `priceColorMode` 필드 추가
- `CryptoTrack/Services/ExchangeManager.swift` — `fetchAssetsPerExchange` / `fetchTickersPerExchange` 추가
- `CryptoTrack/ViewModels/DashboardViewModel.swift` — 새 state, computed, refresh 재작성, 자동 갱신
- `CryptoTrack/Views/Dashboard/DashboardView.swift` — 새 컴포넌트 통합
- `CryptoTrack/Views/Settings/SettingsView.swift` — 표시 설정 섹션 추가

---

## Test Strategy

- **Unit tests** for `DashboardViewModel`: 입력 데이터를 직접 주입(`vm.assets = [...]`, `vm.tickers = [...]`)하고 computed property 검증. 실제 네트워크는 호출하지 않는다.
- **Compile + manual** for SwiftUI Views: 양 플랫폼(`CryptoTrack_macOS`, `CryptoTrack_iOS`) `xcodebuild build` 통과 + 마지막 Task에서 수동 스모크 테스트.

**Test command (단일 테스트):**
```
xcodebuild test -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS \
  -destination 'platform=macOS' \
  -only-testing:CryptoTrackTests_macOS/DashboardViewModelTests/<testName>
```

**Build command (양 플랫폼):**
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_iOS -destination 'generic/platform=iOS' build
```

---

## Task 1: QuoteCurrency enum + Exchange.quoteCurrency

**Files:**
- Create: `CryptoTrack/Models/QuoteCurrency.swift`

- [ ] **Step 1: 새 파일 작성**

```swift
// CryptoTrack/Models/QuoteCurrency.swift
import Foundation

/// 거래소가 자산을 표시할 때 사용하는 기준 통화.
enum QuoteCurrency: String, Sendable, Hashable {
    case krw
    case usdt

    /// 통화 기호 (₩ 또는 $)
    var symbol: String {
        switch self {
        case .krw: return "₩"
        case .usdt: return "$"
        }
    }

    /// UI 표시용 짧은 이름
    var displayName: String {
        switch self {
        case .krw: return "KRW"
        case .usdt: return "USD"
        }
    }
}

extension Exchange {
    /// 이 거래소의 기본 통화. 통화 그룹화의 단일 원천이다.
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

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Models/QuoteCurrency.swift
git commit -m "feat: add QuoteCurrency enum and Exchange.quoteCurrency mapping"
```

---

## Task 2: Asset 헬퍼 + ExchangeFilter enum

**Files:**
- Modify: `CryptoTrack/Models/Asset.swift`
- Create: `CryptoTrack/Models/ExchangeFilter.swift`

- [ ] **Step 1: Asset.swift에 헬퍼 추가**

`CryptoTrack/Models/Asset.swift`의 struct 닫는 `}` 다음에 extension 추가:

```swift
extension Asset {
    /// 평단가가 0 초과면 cost basis 제공으로 간주. 해외 거래소처럼 API가 평단가를
    /// 안 주는 경우 0이 들어오므로 false가 된다.
    var hasCostBasis: Bool { averageBuyPrice > 0 }

    /// 이 자산이 속한 통화 (거래소에서 도출).
    var quoteCurrency: QuoteCurrency { exchange.quoteCurrency }
}
```

최종 파일:

```swift
// CryptoTrack/Models/Asset.swift
import Foundation

/// 거래소 응답을 통합하는 공통 자산 모델
struct Asset: Identifiable, Sendable {
    let id: String
    let symbol: String
    let balance: Double
    let averageBuyPrice: Double
    let exchange: Exchange
    let lastUpdated: Date

    var totalCost: Double {
        balance * averageBuyPrice
    }
}

extension Asset {
    var hasCostBasis: Bool { averageBuyPrice > 0 }
    var quoteCurrency: QuoteCurrency { exchange.quoteCurrency }
}
```

- [ ] **Step 2: ExchangeFilter.swift 생성**

```swift
// CryptoTrack/Models/ExchangeFilter.swift
import Foundation

/// 대시보드 거래소 필터 탭 선택 상태.
enum ExchangeFilter: Hashable, Sendable {
    case all
    case exchange(Exchange)
}
```

- [ ] **Step 3: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 커밋**

```bash
git add CryptoTrack/Models/Asset.swift CryptoTrack/Models/ExchangeFilter.swift
git commit -m "feat: add Asset cost-basis helper and ExchangeFilter enum"
```

---

## Task 3: PriceColorMode + AppSettings 확장 + AppSettingsManager

**Files:**
- Create: `CryptoTrack/Models/PriceColorMode.swift`
- Modify: `CryptoTrack/Models/AppSettings.swift`
- Create: `CryptoTrack/Services/Settings/AppSettingsManager.swift`

- [ ] **Step 1: PriceColorMode.swift 생성**

```swift
// CryptoTrack/Models/PriceColorMode.swift
import Foundation

/// 가격 변동 색상 표시 모드.
enum PriceColorMode: String, Codable, Sendable, CaseIterable {
    /// 한국 표준: 상승=빨강, 하락=파랑
    case korean
    /// 글로벌 표준: 상승=초록, 하락=빨강
    case global

    var displayName: String {
        switch self {
        case .korean: return "한국 (빨/파)"
        case .global: return "글로벌 (초록/빨)"
        }
    }
}
```

- [ ] **Step 2: AppSettings.swift에 priceColorMode 추가**

```swift
// CryptoTrack/Models/AppSettings.swift
import Foundation

/// iCloud 동기화되는 앱 설정 모델입니다.
struct AppSettings: Codable, Sendable {
    var isAppLockEnabled: Bool
    var lastSyncDate: Date
    var priceColorMode: PriceColorMode

    init(
        isAppLockEnabled: Bool = false,
        lastSyncDate: Date = .distantPast,
        priceColorMode: PriceColorMode = .korean
    ) {
        self.isAppLockEnabled = isAppLockEnabled
        self.lastSyncDate = lastSyncDate
        self.priceColorMode = priceColorMode
    }

    enum CodingKeys: String, CodingKey {
        case isAppLockEnabled
        case lastSyncDate
        case priceColorMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isAppLockEnabled = try container.decode(Bool.self, forKey: .isAppLockEnabled)
        self.lastSyncDate = try container.decode(Date.self, forKey: .lastSyncDate)
        // priceColorMode는 기존 iCloud payload엔 없을 수 있으므로 기본값 fallback
        self.priceColorMode = try container.decodeIfPresent(PriceColorMode.self, forKey: .priceColorMode) ?? .korean
    }
}
```

> **메모:** 기존 iCloud KVS에 저장된 AppSettings JSON에는 `priceColorMode` 키가 없을 수 있으므로 `decodeIfPresent`로 fallback한다. 이 한 가지 케이스 때문에 명시적 init이 필요.

- [ ] **Step 3: AppSettingsManager.swift 생성 (디렉토리 신규)**

```swift
// CryptoTrack/Services/Settings/AppSettingsManager.swift
import Foundation
import Observation

/// UserDefaults에 저장되는 표시 설정의 관찰 가능한 단일 진입점.
/// API 키나 기기 비밀은 저장하지 않는다 — 순수 UI/표시 옵션만.
@Observable
@MainActor
final class AppSettingsManager {

    static let shared = AppSettingsManager()

    var priceColorMode: PriceColorMode {
        didSet {
            UserDefaults.standard.set(priceColorMode.rawValue, forKey: Self.priceColorModeKey)
        }
    }

    private static let priceColorModeKey = "settings.priceColorMode"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.priceColorModeKey),
           let mode = PriceColorMode(rawValue: raw) {
            self.priceColorMode = mode
        } else {
            self.priceColorMode = .korean
        }
    }
}
```

- [ ] **Step 4: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add CryptoTrack/Models/PriceColorMode.swift CryptoTrack/Models/AppSettings.swift CryptoTrack/Services/Settings/AppSettingsManager.swift
git commit -m "feat: add PriceColorMode setting and AppSettingsManager"
```

---

## Task 4: PriceColor + PriceFormatter 헬퍼

**Files:**
- Create: `CryptoTrack/Views/Dashboard/Components/PriceColor.swift`
- Create: `CryptoTrack/Views/Dashboard/Components/PriceFormatter.swift`

- [ ] **Step 1: PriceColor.swift 생성**

```swift
// CryptoTrack/Views/Dashboard/Components/PriceColor.swift
import SwiftUI

/// 가격 변동값에 색상을 매핑하는 헬퍼.
enum PriceColor {
    static func color(for value: Double, mode: PriceColorMode) -> Color {
        guard value != 0 else { return .secondary }
        switch mode {
        case .korean:
            return value > 0 ? .red : .blue
        case .global:
            return value > 0 ? .green : .red
        }
    }
}
```

- [ ] **Step 2: PriceFormatter.swift 생성**

```swift
// CryptoTrack/Views/Dashboard/Components/PriceFormatter.swift
import Foundation

/// 통화별 가격 표시 포맷.
enum PriceFormatter {

    private static let krwFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        f.groupingSeparator = ","
        return f
    }()

    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        return f
    }()

    private static let balanceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 8
        return f
    }()

    /// "₩ 12,847,300" 또는 "$ 3,247.50"
    static func formatPrice(_ value: Double, currency: QuoteCurrency) -> String {
        let formatter = currency == .krw ? krwFormatter : usdFormatter
        let number = formatter.string(from: NSNumber(value: value)) ?? "0"
        return "\(currency.symbol) \(number)"
    }

    /// 보유량(소수점 자릿수 가변)
    static func formatBalance(_ value: Double) -> String {
        balanceFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// "+10.74%" / "-3.20%"
    static func formatRate(_ rate: Double) -> String {
        let sign = rate >= 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", rate)
    }
}
```

- [ ] **Step 3: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 커밋**

```bash
git add CryptoTrack/Views/Dashboard/Components/
git commit -m "feat: add PriceColor and PriceFormatter helpers"
```

---

## Task 5: ExchangeManager에 거래소별 fetch 메서드 추가

**Files:**
- Modify: `CryptoTrack/Services/ExchangeManager.swift`

- [ ] **Step 1: 새 메서드 두 개를 ExchangeManager 클래스 안에 추가**

`fetchAllTickers(symbols:)` 메서드 바로 다음(라인 ~108 근처)에 추가:

```swift
    // MARK: - Per-Exchange Fetch (with status tracking)

    /// 등록된 모든 거래소에서 자산을 병렬 조회하되, 거래소별 성공/실패를 그대로 반환합니다.
    /// `fetchAllAssets()`와 달리 일부 실패를 사용자에게 보여주고 싶을 때 사용합니다.
    func fetchAssetsPerExchange() async -> [(Exchange, Result<[Asset], Error>)] {
        guard !registeredExchanges.isEmpty else { return [] }

        return await withTaskGroup(of: (Exchange, Result<[Asset], Error>).self) { group in
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
            for await item in group {
                results.append(item)
            }
            return results
        }
    }

    /// 등록된 모든 거래소에서 시세를 병렬 조회하되, 거래소별 성공/실패를 그대로 반환합니다.
    func fetchTickersPerExchange(symbols: [String]) async -> [(Exchange, Result<[Ticker], Error>)] {
        guard !registeredExchanges.isEmpty else { return [] }

        return await withTaskGroup(of: (Exchange, Result<[Ticker], Error>).self) { group in
            for exchange in registeredExchanges {
                guard let service = services[exchange] else { continue }
                group.addTask {
                    do {
                        let list = try await service.fetchTickers(symbols: symbols)
                        return (exchange, .success(list))
                    } catch {
                        return (exchange, .failure(error))
                    }
                }
            }

            var results: [(Exchange, Result<[Ticker], Error>)] = []
            for await item in group {
                results.append(item)
            }
            return results
        }
    }
```

> **메모:** 기존 `fetchAllAssets`/`fetchAllTickers`는 그대로 둔다. 다른 곳에서 쓰일 수 있고, 이 새 메서드는 ViewModel에서만 사용한다.

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Services/ExchangeManager.swift
git commit -m "feat: add per-exchange fetch methods to ExchangeManager"
```

---

## Task 6: AssetRow 모델

**Files:**
- Create: `CryptoTrack/ViewModels/AssetRow.swift`

- [ ] **Step 1: 파일 작성**

```swift
// CryptoTrack/ViewModels/AssetRow.swift
import Foundation

/// 자산 + 시세를 평탄화한 표시용 행 모델.
/// SwiftUI Table의 KeyPathComparator는 단순 KeyPath만 지원하므로,
/// ticker가 있어야 계산 가능한 값(currentPrice/currentValue/profitRate)을
/// 미리 계산해 노출한다.
struct AssetRow: Identifiable, Sendable {
    let id: String
    let asset: Asset
    let symbol: String
    let exchange: Exchange
    let balance: Double
    let averageBuyPrice: Double
    let currentPrice: Double  // ticker 없으면 0
    let currentValue: Double  // balance * currentPrice
    let profit: Double        // currentValue - balance * averageBuyPrice (cost basis 없으면 0)
    let profitRate: Double    // 수익률 % (cost basis 없으면 0)
    let hasCostBasis: Bool
    let hasTicker: Bool
    let quoteCurrency: QuoteCurrency
}

// Asset이 Hashable이 아니므로 Hashable 자동 synthesis는 불가.
// SwiftUI Table은 Identifiable만 요구하므로 Hashable이 필요 없다.
```

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/ViewModels/AssetRow.swift
git commit -m "feat: add AssetRow flattened display model"
```

---

## Task 7: DashboardViewModelTests — 실패하는 테스트 먼저 작성 (TDD)

**Files:**
- Create: `CryptoTrackTests/DashboardViewModelTests.swift`

이 태스크는 **TDD 빨강 단계**: 새 로직을 사용하는 테스트를 먼저 만들고, 컴파일 실패를 확인한 다음, Task 8에서 ViewModel을 확장한다.

- [ ] **Step 1: 테스트 파일 생성**

```swift
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
```

- [ ] **Step 2: 컴파일 실패 확인 (빨강)**

Run:
```
xcodebuild test -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/DashboardViewModelTests 2>&1 | grep -E "error:|BUILD" | head -10
```

Expected: 컴파일 실패. 에러 메시지에는 다음 중 일부가 포함되어야 한다:
- `selectedFilter`, `hideDust`, `displayedRows`, `krwSummary`, `usdSummary` 같은 멤버 미정의
- 또는 `init(exchangeManager:)` 시그니처가 맞지 않음

이 실패는 정상이다 — 다음 태스크에서 ViewModel을 확장해 이 멤버들을 추가한다.

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrackTests/DashboardViewModelTests.swift
git commit -m "test: add failing DashboardViewModel tests for new behavior"
```

---

## Task 8: DashboardViewModel 확장 (TDD 초록 단계)

**Files:**
- Modify: `CryptoTrack/ViewModels/DashboardViewModel.swift`

이 태스크가 가장 큰 변경입니다. 기존 메서드(`refresh`, `ticker(for:)`, `currentValue(for:)`)를 수정하고 새 state/computed를 추가합니다.

- [ ] **Step 1: ViewModel 전체 재작성**

`CryptoTrack/ViewModels/DashboardViewModel.swift` 전체를 다음으로 교체:

```swift
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

        let symbols = Array(Set(newAssets.map(\.symbol)))
        let tickerResults = await exchangeManager.fetchTickersPerExchange(symbols: symbols)

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
```

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD" | head -10
```

Expected: `** BUILD SUCCEEDED **`

> **메모:** 기존 `DashboardView`가 ViewModel의 옛 멤버(`totalValue`, `totalProfit`, `totalProfitRate`, `profit(for:)`, `profitRate(for:)`)를 참조하고 있을 수 있다. 빌드 에러가 나면 일단 그 멤버들을 ViewModel에 임시로 deprecated wrapper로 추가해 빌드만 통과시킨다 — Task 16에서 DashboardView를 재구성할 때 모두 제거된다.

만약 빌드 에러가 나면 ViewModel 끝에 다음을 추가:

```swift
    // MARK: - Deprecated (Task 16에서 DashboardView 재구성 시 제거)

    /// @deprecated `krwSummary`/`usdSummary` 사용
    var totalValue: Double {
        (krwSummary?.totalValue ?? 0) + (usdSummary?.totalValue ?? 0)
    }
    var totalCost: Double {
        (krwSummary?.totalCost ?? 0) + (usdSummary?.totalCost ?? 0)
    }
    var totalProfit: Double { totalValue - totalCost }
    var totalProfitRate: Double {
        guard totalCost > 0 else { return 0 }
        return (totalProfit / totalCost) * 100
    }
    func profit(for asset: Asset) -> Double {
        currentValue(for: asset) - asset.totalCost
    }
    func profitRate(for asset: Asset) -> Double {
        guard asset.totalCost > 0 else { return 0 }
        return (profit(for: asset) / asset.totalCost) * 100
    }
```

다시 빌드:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 테스트 실행 (초록)**

Run:
```
xcodebuild test -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/DashboardViewModelTests 2>&1 | tail -20
```

Expected: 모든 테스트 통과 (`** TEST SUCCEEDED **` 또는 13개 테스트 모두 PASS)

- [ ] **Step 4: 커밋**

```bash
git add CryptoTrack/ViewModels/DashboardViewModel.swift
git commit -m "feat: rewrite DashboardViewModel with filters, summaries, and auto-refresh

- Strict ticker matching (exchange + symbol must match exactly)
- Remove cost-basis fallback in currentValue (root cause of 평가액=매수금액 bug)
- Add displayedRows with filter/dust/sort pipeline
- Add krwSummary/usdSummary for two-currency display
- Refresh now tracks per-exchange success/failure
- Auto-refresh loop via SwiftUI .task cancellation"
```

---

## Task 9: ProfitBadge 컴포넌트

**Files:**
- Create: `CryptoTrack/Views/Dashboard/Components/ProfitBadge.swift`

- [ ] **Step 1: 파일 작성**

```swift
// CryptoTrack/Views/Dashboard/Components/ProfitBadge.swift
import SwiftUI

/// 수익률(%)과 손익 금액을 표시하는 작은 배지.
struct ProfitBadge: View {
    let rate: Double
    let profit: Double?       // nil이면 금액 미표시 (요약 카드에서는 표시, 테이블 셀에서는 숨김)
    let currency: QuoteCurrency?
    let colorMode: PriceColorMode

    init(
        rate: Double,
        profit: Double? = nil,
        currency: QuoteCurrency? = nil,
        colorMode: PriceColorMode
    ) {
        self.rate = rate
        self.profit = profit
        self.currency = currency
        self.colorMode = colorMode
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(PriceFormatter.formatRate(rate))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PriceColor.color(for: rate, mode: colorMode))
                .monospacedDigit()
            if let profit, let currency {
                Text(PriceFormatter.formatPrice(profit, currency: currency))
                    .font(.caption2)
                    .foregroundStyle(PriceColor.color(for: profit, mode: colorMode))
                    .monospacedDigit()
            }
        }
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Dashboard/Components/ProfitBadge.swift
git commit -m "feat: add ProfitBadge component"
```

---

## Task 10: AssetFilterTabBar 컴포넌트

**Files:**
- Create: `CryptoTrack/Views/Dashboard/AssetFilterTabBar.swift`

- [ ] **Step 1: 파일 작성**

```swift
// CryptoTrack/Views/Dashboard/AssetFilterTabBar.swift
import SwiftUI

/// 대시보드 상단의 거래소 필터 탭 바.
/// "전체" + 등록된 거래소들만 동적으로 표시한다.
struct AssetFilterTabBar: View {
    @Binding var selected: ExchangeFilter
    let available: [Exchange]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "전체",
                    isSelected: selected == .all
                ) {
                    selected = .all
                }
                ForEach(available, id: \.self) { exchange in
                    FilterChip(
                        label: exchange.rawValue,
                        isSelected: selected == .exchange(exchange)
                    ) {
                        selected = .exchange(exchange)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var filter: ExchangeFilter = .all
    return AssetFilterTabBar(
        selected: $filter,
        available: [.upbit, .bithumb, .binance]
    )
    .padding()
}
```

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Dashboard/AssetFilterTabBar.swift
git commit -m "feat: add AssetFilterTabBar component"
```

---

## Task 11: PortfolioSummaryCard 컴포넌트

**Files:**
- Create: `CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift`

> **메모:** 기존 `PortfolioSummaryView`는 Task 15(DashboardView 재구성)에서 사용처가 모두 사라지면 그때 삭제. 지금은 새 컴포넌트만 추가하고 기존 것은 건드리지 않는다.

- [ ] **Step 1: 파일 작성**

```swift
// CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift
import SwiftUI

/// KRW와 USD 그룹을 두 줄로 분리해 표시하는 요약 카드.
/// 한쪽 통화 자산이 없으면 그쪽은 그리지 않는다.
struct PortfolioSummaryCard: View {
    let krw: CurrencySummary?
    let usd: CurrencySummary?
    let colorMode: PriceColorMode

    var body: some View {
        VStack(spacing: 12) {
            if let krw {
                SummaryRow(summary: krw, colorMode: colorMode)
            }
            if krw != nil && usd != nil {
                Divider()
            }
            if let usd {
                SummaryRow(summary: usd, colorMode: colorMode)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.secondary)
        )
    }
}

private struct SummaryRow: View {
    let summary: CurrencySummary
    let colorMode: PriceColorMode

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.currency.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(PriceFormatter.formatPrice(summary.totalValue, currency: summary.currency))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ProfitBadge(
                    rate: summary.profitRate,
                    profit: summary.totalProfit,
                    currency: summary.currency,
                    colorMode: colorMode
                )
                if summary.hasUnknownCostBasis {
                    Text("일부 자산 평단가 미제공")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

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
        colorMode: .korean
    )
    .padding()
}
```

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift
git commit -m "feat: add PortfolioSummaryCard with KRW/USD split"
```

---

## Task 12: DashboardToolbar 컴포넌트

**Files:**
- Create: `CryptoTrack/Views/Dashboard/DashboardToolbar.swift`

- [ ] **Step 1: 파일 작성**

```swift
// CryptoTrack/Views/Dashboard/DashboardToolbar.swift
import SwiftUI

/// 대시보드 상단의 컨트롤 바: dust 토글, 마지막 갱신 시각, 새로고침 버튼.
struct DashboardToolbar: View {
    @Binding var hideDust: Bool
    let lastRefresh: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $hideDust) {
                Text("소액 숨김")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            #if os(macOS)
            .controlSize(.mini)
            #endif

            Spacer()

            if let lastRefresh {
                Text("갱신: \(formatTime(lastRefresh))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    @Previewable @State var hide = true
    return DashboardToolbar(
        hideDust: $hide,
        lastRefresh: Date(),
        isRefreshing: false,
        onRefresh: {}
    )
    .padding()
}
```

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Dashboard/DashboardToolbar.swift
git commit -m "feat: add DashboardToolbar with dust toggle and refresh"
```

---

## Task 13: ExchangeStatusBanner 컴포넌트

**Files:**
- Create: `CryptoTrack/Views/Dashboard/ExchangeStatusBanner.swift`

- [ ] **Step 1: 파일 작성**

```swift
// CryptoTrack/Views/Dashboard/ExchangeStatusBanner.swift
import SwiftUI

/// 일부 거래소만 fetch 실패했을 때 표시하는 경고 배너.
struct ExchangeStatusBanner: View {
    let statuses: [ExchangeFetchStatus]

    private var failedStatuses: [ExchangeFetchStatus] {
        statuses.filter { $0.status == .failed }
    }

    var body: some View {
        if failedStatuses.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headlineText)
                        .font(.caption.weight(.semibold))
                    if let first = failedStatuses.first, let err = first.lastError {
                        Text("\(first.id.rawValue): \(err)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.15))
            )
        }
    }

    private var headlineText: String {
        let count = failedStatuses.count
        return "\(count)개 거래소 갱신 실패"
    }
}

#Preview {
    ExchangeStatusBanner(statuses: [
        .init(id: .upbit, status: .success, lastError: nil),
        .init(id: .bithumb, status: .failed, lastError: "401 Unauthorized"),
    ])
    .padding()
}
```

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Dashboard/ExchangeStatusBanner.swift
git commit -m "feat: add ExchangeStatusBanner for partial fetch failures"
```

---

## Task 14: AssetTable (macOS)

**Files:**
- Create: `CryptoTrack/Views/Dashboard/AssetTable.swift`

- [ ] **Step 1: 파일 작성**

```swift
// CryptoTrack/Views/Dashboard/AssetTable.swift
#if os(macOS)
import SwiftUI

/// macOS 전용: SwiftUI Table로 자산 목록을 컴팩트하게 표시.
/// 컬럼 헤더 클릭 시 정렬은 SwiftUI Table이 자동 처리한다 (KeyPathComparator 바인딩).
struct AssetTable: View {
    let rows: [AssetRow]
    @Binding var sortOrder: [KeyPathComparator<AssetRow>]
    let colorMode: PriceColorMode

    var body: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("코인") { row in
                HStack(spacing: 8) {
                    Text(row.symbol)
                        .font(.body.weight(.semibold))
                    Text(row.exchange.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.15))
                        )
                }
            }
            .width(min: 120, ideal: 140)

            TableColumn("보유량", value: \.balance) { row in
                Text(PriceFormatter.formatBalance(row.balance))
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn("평단가", value: \.averageBuyPrice) { row in
                if row.hasCostBasis {
                    Text(PriceFormatter.formatPrice(row.averageBuyPrice, currency: row.quoteCurrency))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("현재가", value: \.currentPrice) { row in
                if row.hasTicker {
                    Text(PriceFormatter.formatPrice(row.currentPrice, currency: row.quoteCurrency))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("평가금액", value: \.currentValue) { row in
                Text(PriceFormatter.formatPrice(row.currentValue, currency: row.quoteCurrency))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .width(min: 110, ideal: 140)

            TableColumn("수익률", value: \.profitRate) { row in
                if row.hasCostBasis {
                    HStack(spacing: 4) {
                        Text(PriceFormatter.formatRate(row.profitRate))
                            .foregroundStyle(PriceColor.color(for: row.profitRate, mode: colorMode))
                            .monospacedDigit()
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)
        }
    }
}

#Preview {
    @Previewable @State var sortOrder: [KeyPathComparator<AssetRow>] = [
        KeyPathComparator(\AssetRow.currentValue, order: .reverse)
    ]
    let sample = DashboardViewModel.preview.displayedRows
    return AssetTable(rows: sample, sortOrder: $sortOrder, colorMode: .korean)
        .frame(minWidth: 800, minHeight: 400)
}
#endif
```

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Dashboard/AssetTable.swift
git commit -m "feat: add AssetTable for macOS with sortable columns"
```

---

## Task 15: AssetCardList (iOS)

**Files:**
- Create: `CryptoTrack/Views/Dashboard/AssetCardList.swift`

- [ ] **Step 1: 파일 작성**

```swift
// CryptoTrack/Views/Dashboard/AssetCardList.swift
#if !os(macOS)
import SwiftUI

/// iOS 전용: 카드형 행으로 자산 목록을 표시.
struct AssetCardList: View {
    let rows: [AssetRow]
    let colorMode: PriceColorMode

    var body: some View {
        List(rows) { row in
            AssetCardRow(row: row, colorMode: colorMode)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .listStyle(.plain)
    }
}

private struct AssetCardRow: View {
    let row: AssetRow
    let colorMode: PriceColorMode

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.symbol)
                        .font(.headline)
                    Text("\(row.exchange.rawValue) · \(PriceFormatter.formatBalance(row.balance)) \(row.symbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PriceFormatter.formatPrice(row.currentValue, currency: row.quoteCurrency))
                        .font(.headline)
                        .monospacedDigit()
                    if row.hasCostBasis {
                        Text(PriceFormatter.formatRate(row.profitRate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PriceColor.color(for: row.profitRate, mode: colorMode))
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack(spacing: 16) {
                infoPair(
                    label: "평단",
                    value: row.hasCostBasis
                        ? PriceFormatter.formatPrice(row.averageBuyPrice, currency: row.quoteCurrency)
                        : "—"
                )
                infoPair(
                    label: "현재가",
                    value: row.hasTicker
                        ? PriceFormatter.formatPrice(row.currentPrice, currency: row.quoteCurrency)
                        : "—"
                )
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background.secondary)
        )
    }

    private func infoPair(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}

#Preview {
    let sample = DashboardViewModel.preview.displayedRows
    return AssetCardList(rows: sample, colorMode: .korean)
}
#endif
```

- [ ] **Step 2: iOS 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_iOS -destination 'generic/platform=iOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Dashboard/AssetCardList.swift
git commit -m "feat: add AssetCardList for iOS with card-style rows"
```

---

## Task 16: DashboardView 컨테이너 재구성

**Files:**
- Modify: `CryptoTrack/Views/Dashboard/DashboardView.swift`

이 태스크가 마지막 통합 단계입니다. 기존 `portfolioList`, `PortfolioSummaryView`, `AssetRowView`(이 파일 안의 옛 행 컴포넌트) 사용을 모두 제거하고 새 컴포넌트로 교체합니다.

- [ ] **Step 1: DashboardView 전체 재작성**

`CryptoTrack/Views/Dashboard/DashboardView.swift` 전체를 다음으로 교체:

```swift
import SwiftUI

/// 포트폴리오 대시보드 메인 화면입니다.
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var settingsManager = AppSettingsManager.shared

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("대시보드")
                .task {
                    await viewModel.runAutoRefreshLoop()
                }
                .refreshable {
                    await viewModel.refresh()
                }
        }
    }

    // MARK: - Content States

    private var hasNoExchanges: Bool {
        ExchangeManager.shared.registeredExchanges.isEmpty
    }

    private var registeredExchanges: [Exchange] {
        ExchangeManager.shared.registeredExchanges
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.assets.isEmpty {
            loadingView
        } else if hasNoExchanges {
            emptyStateView
        } else if let error = viewModel.errorMessage, viewModel.assets.isEmpty {
            errorView(message: error)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        VStack(spacing: 12) {
            AssetFilterTabBar(
                selected: $viewModel.selectedFilter,
                available: registeredExchanges
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)

            PortfolioSummaryCard(
                krw: viewModel.krwSummary,
                usd: viewModel.usdSummary,
                colorMode: settingsManager.priceColorMode
            )
            .padding(.horizontal, 16)

            ExchangeStatusBanner(statuses: viewModel.exchangeStatuses)
                .padding(.horizontal, 16)

            DashboardToolbar(
                hideDust: $viewModel.hideDust,
                lastRefresh: viewModel.lastRefreshDate,
                isRefreshing: viewModel.isLoading,
                onRefresh: { Task { await viewModel.refresh() } }
            )
            .padding(.horizontal, 16)

            assetsList
                .frame(maxHeight: .infinity)
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
                colorMode: settingsManager.priceColorMode
            )
            #else
            AssetCardList(
                rows: viewModel.displayedRows,
                colorMode: settingsManager.priceColorMode
            )
            #endif
        }
    }

    // MARK: - Empty/Loading/Error states

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("연결된 거래소가 없습니다")
                .font(.title3.bold())
            Text("설정 탭에서 거래소 API를 등록하면\n자산 현황을 확인할 수 있습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilterView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
            if viewModel.hideDust && hasOnlyDust {
                Text("표시할 자산이 없습니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("소액 숨김 해제") {
                    viewModel.hideDust = false
                }
                .buttonStyle(.borderless)
            } else {
                Text("선택한 거래소에 보유 자산이 없습니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 필터 결과는 비었지만 dust를 켜면 자산이 보일지 판단.
    private var hasOnlyDust: Bool {
        let unfilteredCount = viewModel.assets.filter { asset in
            switch viewModel.selectedFilter {
            case .all: return true
            case .exchange(let ex): return asset.exchange == ex
            }
        }.count
        return unfilteredCount > 0 && viewModel.displayedRows.isEmpty
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                #if os(macOS)
                .controlSize(.large)
                #else
                .scaleEffect(1.5)
                #endif
            Text("불러오는 중…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("오류가 발생했습니다")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
}
```

> **메모:** 기존 파일에 있던 `_DashboardPreviewWrapper`, `PortfolioSummaryView`, `AssetRowView` 같은 컴포넌트는 더 이상 사용되지 않으므로 모두 제거됨. 만약 다른 파일에서 `PortfolioSummaryView`나 `AssetRowView`를 참조하고 있으면 빌드 에러가 날 것이고, 그 경우 해당 파일도 정리한다.

- [ ] **Step 2: 누락된 컴포넌트 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | grep -E "error:" | head -10
```

만약 `Cannot find 'PortfolioSummaryView'` 또는 `Cannot find 'AssetRowView'` 같은 에러가 다른 파일에서 나면, 그 파일을 함께 정리한다 (보통 별도 파일로 분리되어 있지 않고 DashboardView 안에 있었다면 위 재작성으로 이미 제거됨).

- [ ] **Step 3: ViewModel의 deprecated wrapper 제거**

Task 8에서 추가했던 `totalValue`/`totalCost`/`totalProfit`/`totalProfitRate`/`profit(for:)`/`profitRate(for:)`가 더 이상 참조되지 않으므로 ViewModel에서 삭제. `DashboardViewModel.swift`에서 `// MARK: - Deprecated` 섹션과 그 아래 메서드들을 모두 제거.

- [ ] **Step 4: 양 플랫폼 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_iOS -destination 'generic/platform=iOS' build 2>&1 | tail -3
```

Expected: 두 번 모두 `** BUILD SUCCEEDED **`

- [ ] **Step 5: 테스트 재실행 (regression 체크)**

Run:
```
xcodebuild test -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' -only-testing:CryptoTrackTests_macOS/DashboardViewModelTests 2>&1 | tail -10
```

Expected: 모든 테스트 통과

- [ ] **Step 6: 커밋**

```bash
git add CryptoTrack/Views/Dashboard/DashboardView.swift CryptoTrack/ViewModels/DashboardViewModel.swift
git commit -m "feat: rebuild DashboardView with new filter/summary/table components"
```

---

## Task 17: SettingsView에 표시 설정 섹션 추가

**Files:**
- Modify: `CryptoTrack/Views/Settings/SettingsView.swift`

- [ ] **Step 1: 표시 설정 섹션을 SecuritySectionView 위에 추가**

`SettingsView.swift`의 `body` 안에서 `Section`들 사이에 `DisplaySettingsSectionView`를 추가. 그리고 파일 맨 아래에 새 컴포넌트를 정의:

`SettingsView`의 body 변경 — `SecuritySectionView` 호출 직전에 추가:

```swift
                DisplaySettingsSectionView()

                SecuritySectionView(lockManager: lockManager)
```

파일 맨 아래(iCloudSyncSectionView 다음, `// MARK: - Preview` 직전)에 새 컴포넌트 정의:

```swift
// MARK: - Display Section

private struct DisplaySettingsSectionView: View {
    @State private var settings = AppSettingsManager.shared

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { settings.priceColorMode },
                set: { settings.priceColorMode = $0 }
            )) {
                ForEach(PriceColorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(.purple)
                    Text("가격 변동 색상")
                }
            }
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.menu)
            #endif
        } header: {
            Text("표시")
        } footer: {
            Text("한국 표준은 상승=빨강, 하락=파랑입니다. 글로벌 표준은 상승=초록, 하락=빨강입니다.")
        }
    }
}
```

- [ ] **Step 2: 양 플랫폼 빌드 확인**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_iOS -destination 'generic/platform=iOS' build 2>&1 | tail -3
```

Expected: 두 번 모두 `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Settings/SettingsView.swift
git commit -m "feat: add display section in Settings with price color mode picker"
```

---

## Task 18: 양 플랫폼 빌드 + 전체 테스트 + 수동 검증

**Files:** None — 검증 단계.

- [ ] **Step 1: macOS 빌드 클린**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' clean build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: iOS 빌드 클린**

Run:
```
xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_iOS -destination 'generic/platform=iOS' clean build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 전체 테스트 실행**

Run:
```
xcodebuild test -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `Test Suite 'All tests' passed` (또는 `** TEST SUCCEEDED **`)

- [ ] **Step 4: 수동 스모크 테스트 (Xcode에서 실행)**

Xcode에서 macOS 앱을 실행하고 다음을 직접 확인:

1. **거래소 미등록 상태** — "연결된 거래소가 없습니다" 표시
2. **업비트 등록 후** — 대시보드 진입
   - [ ] 상단에 "전체 | 업비트" 탭 표시
   - [ ] KRW 요약 카드 표시 (총 평가액 + 수익률 — 매수금액과 다른 값이어야 함)
   - [ ] 자산 테이블에 코인별 6개 컬럼 표시
   - [ ] 평가금액 컬럼 헤더 클릭 시 정렬 토글
   - [ ] 소액 숨김 토글 동작
3. **빗썸 추가 등록** — 양쪽 거래소 자산이 KRW 요약에 합산
4. **바이낸스 추가 등록 (가능하면)**
   - [ ] USD 요약 카드가 KRW 카드와 별도 줄로 추가
   - [ ] 바이낸스 자산은 평단가/수익률이 "—"로 표시
   - [ ] "일부 자산 평단가 미제공" 부가 텍스트 표시
5. **30초 대기** — 자동 갱신 발생, lastRefresh 시각 업데이트
6. **설정 → 표시 → 색상 모드 변경**
   - [ ] 글로벌로 바꾸면 수익률 색이 빨/파에서 초록/빨로 즉시 전환
7. **빗썸 인증 의도적 실패** (잘못된 키로 등록)
   - [ ] 데이터는 정상 거래소만 보이고, 상단에 ExchangeStatusBanner 노출

- [ ] **Step 5: 최종 커밋 (필요 시)**

수동 테스트 중 발견한 작은 폴리시(여백/색상/라벨) 조정이 있다면 한 커밋으로 모아 마무리:

```bash
git add -A
git commit -m "fix: dashboard polish from manual smoke test"
```

만약 수정사항이 없으면 이 스텝은 건너뜀.

---

## 완료 후

- 모든 태스크 체크박스가 체크되어야 한다.
- `git log --oneline | head -20` 으로 일련의 commit 히스토리 확인.
- `superpowers:finishing-a-development-branch` 스킬로 develop 머지 진행.
