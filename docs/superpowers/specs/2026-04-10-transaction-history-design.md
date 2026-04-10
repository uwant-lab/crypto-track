# 거래 내역 (체결/입금) 조회 기능 설계

## 개요

7개 거래소(Upbit, Binance, Bithumb, Bybit, Coinone, Korbit, OKX)의 체결 내역과 입금 내역을 조회하는 기능을 추가한다. 주문조회 권한과 입금조회 권한으로 사용 가능한 API만 사용한다.

## 범위

- **체결 내역**: 완료된 주문만 (매수/매도). 미체결·취소 제외.
- **입금 내역**: 코인 입금 + 원화(법정화폐) 입금.
- **대상 코인**: 전체 (API가 돌려주는 모든 코인)
- **기간**: 사용자 선택. 긴 기간(수 년)도 내부 페이지네이션으로 처리.

---

## 공통 모델

### Order (체결 내역)

```swift
struct Order: Identifiable, Sendable {
    let id: String
    let symbol: String          // "BTC", "ETH"
    let side: OrderSide         // .buy, .sell
    let price: Double           // 체결 단가
    let amount: Double          // 체결 수량
    let totalValue: Double      // 체결 금액 (price × amount)
    let fee: Double             // 수수료
    let exchange: Exchange
    let executedAt: Date        // 체결 시각
}

enum OrderSide: String, Sendable {
    case buy
    case sell
}
```

### Deposit (입금 내역)

```swift
struct Deposit: Identifiable, Sendable {
    let id: String
    let symbol: String          // "BTC", "KRW"
    let amount: Double          // 입금 수량/금액
    let type: DepositType       // .crypto, .fiat
    let status: DepositStatus   // .completed, .pending, .cancelled
    let txId: String?           // 블록체인 트랜잭션 해시 (코인만)
    let exchange: Exchange
    let completedAt: Date       // 완료 시각
}

enum DepositType: String, Sendable {
    case crypto
    case fiat
}

enum DepositStatus: String, Sendable {
    case completed
    case pending
    case cancelled
}
```

### PagedResult (페이지네이션)

```swift
struct PagedResult<T: Sendable>: Sendable {
    let items: [T]
    let hasMore: Bool
    let progress: Double        // 0.0~1.0
}
```

---

## ExchangeService 프로토콜 확장

기존 `ExchangeService`에 2개 메서드를 추가한다.

```swift
protocol ExchangeService: Sendable {
    // ... 기존 메서드 유지 ...

    /// 체결 완료된 주문 내역을 조회합니다.
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order>

    /// 입금 내역을 조회합니다.
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit>
}
```

### 페이지네이션 전략

- 각 거래소 구현체가 내부적으로 API 제한(건수/기간)을 처리한다.
- ViewModel은 `page`를 0부터 증가시키며 `hasMore == false`가 될 때까지 반복 호출한다.
- 긴 기간 조회 시: 구현체 내부에서 API 제한에 맞게 기간을 분할하여 호출한다. 외부(ViewModel)에서는 단순히 page를 증가시키기만 한다.

---

## 거래소별 API 매핑

| 거래소 | 체결 내역 엔드포인트 | 입금 내역 엔드포인트 | 페이지 제한 |
|--------|---------------------|---------------------|------------|
| Upbit | `GET /v1/orders/closed` | `GET /v1/deposits` | 100건/페이지 |
| Binance | `GET /api/v3/myTrades` | `GET /sapi/v1/capital/deposit/hisrec` | 1000건/페이지 |
| Bithumb | `POST /info/orders` | `POST /info/user_transactions` (type=4) | 100건/페이지 |
| Bybit | `GET /v5/execution/list` | `GET /v5/asset/deposit/query-record` | 100건/페이지 |
| Coinone | `GET /v2.1/order/completed_orders` | `GET /v2.1/account/deposit` | 100건/페이지 |
| Korbit | `GET /v1/user/orders` (status=filled) | `GET /v1/user/transfers` (type=deposit) | 40건/페이지 |
| OKX | `GET /api/v5/trade/fills-history` | `GET /api/v5/asset/deposit-history` | 100건/페이지 |

### 거래소별 특이사항

- **Binance**: `myTrades`는 심볼 파라미터 필수. 보유 자산 심볼 목록을 먼저 조회한 뒤 심볼별로 순회한다.
- **Bithumb**: POST 기반 API. request body에 기간/페이징 파라미터 설정.
- **Korbit**: 페이지당 최대 40건으로 제한이 가장 작음.
- **OKX**: `fills-history`는 최근 3개월만 지원. 이전 기간은 `fills-history-archive` 엔드포인트 사용.

---

## UI 구조

### 사이드바 메뉴

`AdaptiveRootView`의 macOS 사이드바 및 iOS TabView에 "거래 내역" 메뉴를 추가한다.

```
macOS 사이드바           iOS TabView
├── 대시보드 (기존)      ├── 대시보드 (기존)
├── 거래 내역 (신규)     ├── 거래 내역 (신규)
└── 설정 (기존)          └── 설정 (기존)
```

### TransactionHistoryView

```
┌─────────────────────────────────────────────┐
│  거래 내역                                    │
│                                              │
│  [체결 내역]  [입금 내역]    ← 탭 전환         │
│                                              │
│  ┌ 필터 ─────────────────────────────────┐   │
│  │ 거래소: [전체 ▾]   기간: [시작일] ~ [종료일] │
│  │                          [조회]       │   │
│  └───────────────────────────────────────┘   │
│                                              │
│  ── 2024.12.15 ─────────────────────────── │
│  BTC  매수  50,000,000원  0.001BTC          │
│  ETH  매도   3,200,000원  0.5ETH            │
│  ── 2024.12.14 ─────────────────────────── │
│  XRP  매수     500,000원  1000XRP           │
│  ...                                         │
│                                              │
│  ████████████░░░░ 65% (650건 로드됨)         │
│                                              │
└─────────────────────────────────────────────┘
```

### UI 요소

- **탭 전환**: Picker 또는 segmented control로 체결/입금 전환
- **필터**: 거래소 드롭다운 (전체 + 등록된 거래소) + DatePicker (시작일/종료일) + 조회 버튼
- **리스트**: 날짜별 Section 그루핑. 매수는 초록, 매도는 빨강으로 구분.
- **프로그레스 바**: 하단에 진행률 + 로드된 건수 표시
- **점진적 로딩**: 페이지 응답마다 리스트에 즉시 추가

---

## ViewModel

### TransactionHistoryViewModel

```swift
@Observable
@MainActor
final class TransactionHistoryViewModel {
    // State
    var selectedTab: Tab = .orders          // .orders, .deposits
    var selectedExchange: Exchange? = nil    // nil = 전체
    var dateFrom: Date                       // 기본값: 1개월 전
    var dateTo: Date                         // 기본값: 오늘
    var orders: [Order] = []
    var deposits: [Deposit] = []
    var isLoading: Bool = false
    var progress: Double = 0.0
    var errorMessage: String? = nil
    var loadedCount: Int = 0

    // Methods
    func fetchOrders() async                 // 페이지 반복 호출, 점진적 추가
    func fetchDeposits() async               // 페이지 반복 호출, 점진적 추가
    func cancel()                            // 진행 중인 조회 취소

    // Computed
    var groupedOrders: [(Date, [Order])]     // 날짜별 그루핑
    var groupedDeposits: [(Date, [Deposit])] // 날짜별 그루핑
}
```

### 점진적 로딩 흐름

1. 사용자가 기간 선택 후 "조회" 탭
2. `selectedExchange`가 nil이면 등록된 전체 거래소를 순회
3. 거래소별로 `fetchOrders(from:to:page:)` 반복 호출
4. 매 페이지 응답마다 `orders`에 append → UI 즉시 반영
5. `progress` 업데이트 → 프로그레스 바 갱신
6. `hasMore == false`가 되면 다음 거래소로 이동
7. 전체 완료 시 `isLoading = false`

### 취소 정책

- **탭 이동 시**: 조회 계속 유지 (백그라운드 로딩)
- **조건 변경 시**: `Task.cancel()`로 기존 조회 중단 후 새 조회 시작

---

## 파일 구조

### 신규 파일

```
CryptoTrack/
├── Models/
│   ├── Order.swift                          // Order, OrderSide
│   ├── Deposit.swift                        // Deposit, DepositType, DepositStatus
│   └── PagedResult.swift                    // PagedResult<T>
├── ViewModels/
│   └── TransactionHistoryViewModel.swift
├── Views/
│   └── TransactionHistory/
│       ├── TransactionHistoryView.swift      // 메인 화면 (탭 + 필터)
│       ├── OrderListView.swift               // 체결 내역 리스트
│       └── DepositListView.swift             // 입금 내역 리스트
└── Services/Exchange/
    ├── Upbit/UpbitService.swift              // fetchOrders, fetchDeposits 추가
    ├── Binance/BinanceService.swift          // fetchOrders, fetchDeposits 추가
    ├── Bithumb/BithumbService.swift          // fetchOrders, fetchDeposits 추가
    ├── Bybit/BybitService.swift              // fetchOrders, fetchDeposits 추가
    ├── Coinone/CoinoneService.swift          // fetchOrders, fetchDeposits 추가
    ├── Korbit/KorbitService.swift            // fetchOrders, fetchDeposits 추가
    └── OKX/OKXService.swift                 // fetchOrders, fetchDeposits 추가
```

### 수정 파일

```
CryptoTrack/
├── Services/Exchange/ExchangeService.swift   // 프로토콜에 메서드 2개 추가
├── DesignSystem/PlatformAdaptiveLayout.swift // 사이드바/탭바에 메뉴 추가
└── Services/Exchange/*/Models.swift          // 거래소별 응답 모델 추가
```
