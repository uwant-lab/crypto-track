# 거래 내역 (체결/입금) 조회 기능 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 7개 거래소의 체결 완료 주문 내역과 입금 내역을 점진적 로딩으로 조회하는 기능을 추가한다.

**Architecture:** ExchangeService 프로토콜에 `fetchOrders`/`fetchDeposits` 메서드를 추가하고, 7개 거래소 각각에서 구현한다. TransactionHistoryViewModel이 페이지 단위로 반복 호출하며 UI에 점진적으로 반영한다. AdaptiveRootView에 "거래 내역" 메뉴를 추가한다.

**Tech Stack:** SwiftUI, async/await, Grid, Picker, DatePicker, `#if os(macOS)` conditional compilation

**Spec:** `docs/superpowers/specs/2026-04-10-transaction-history-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `CryptoTrack/Models/Order.swift` | Order, OrderSide 모델 |
| Create | `CryptoTrack/Models/Deposit.swift` | Deposit, DepositType, DepositStatus 모델 |
| Create | `CryptoTrack/Models/PagedResult.swift` | PagedResult<T> 제네릭 모델 |
| Modify | `CryptoTrack/Services/Exchange/ExchangeService.swift` | 프로토콜에 fetchOrders/fetchDeposits 추가 |
| Modify | `CryptoTrack/Services/Exchange/Upbit/UpbitModels.swift` | Upbit 주문/입금 응답 모델 |
| Modify | `CryptoTrack/Services/Exchange/Upbit/UpbitService.swift` | fetchOrders/fetchDeposits 구현 |
| Modify | `CryptoTrack/Services/Exchange/Binance/BinanceModels.swift` | Binance 주문/입금 응답 모델 |
| Modify | `CryptoTrack/Services/Exchange/Binance/BinanceService.swift` | fetchOrders/fetchDeposits 구현 |
| Modify | `CryptoTrack/Services/Exchange/Bithumb/BithumbModels.swift` | Bithumb 주문/입금 응답 모델 |
| Modify | `CryptoTrack/Services/Exchange/Bithumb/BithumbService.swift` | fetchOrders/fetchDeposits 구현 |
| Modify | `CryptoTrack/Services/Exchange/Bybit/BybitModels.swift` | Bybit 주문/입금 응답 모델 |
| Modify | `CryptoTrack/Services/Exchange/Bybit/BybitService.swift` | fetchOrders/fetchDeposits 구현 |
| Modify | `CryptoTrack/Services/Exchange/Coinone/CoinoneModels.swift` | Coinone 주문/입금 응답 모델 |
| Modify | `CryptoTrack/Services/Exchange/Coinone/CoinoneService.swift` | fetchOrders/fetchDeposits 구현 |
| Modify | `CryptoTrack/Services/Exchange/Korbit/KorbitModels.swift` | Korbit 주문/입금 응답 모델 |
| Modify | `CryptoTrack/Services/Exchange/Korbit/KorbitService.swift` | fetchOrders/fetchDeposits 구현 |
| Modify | `CryptoTrack/Services/Exchange/OKX/OKXModels.swift` | OKX 주문/입금 응답 모델 |
| Modify | `CryptoTrack/Services/Exchange/OKX/OKXService.swift` | fetchOrders/fetchDeposits 구현 |
| Create | `CryptoTrack/ViewModels/TransactionHistoryViewModel.swift` | 거래 내역 상태 관리 + 점진적 로딩 |
| Create | `CryptoTrack/Views/TransactionHistory/TransactionHistoryView.swift` | 메인 화면 (탭 + 필터) |
| Create | `CryptoTrack/Views/TransactionHistory/OrderListView.swift` | 체결 내역 리스트 |
| Create | `CryptoTrack/Views/TransactionHistory/DepositListView.swift` | 입금 내역 리스트 |
| Modify | `CryptoTrack/DesignSystem/PlatformAdaptiveLayout.swift` | 사이드바/탭바에 메뉴 추가 |

---

### Task 1: 공통 모델 생성 (Order, Deposit, PagedResult)

**Files:**
- Create: `CryptoTrack/Models/Order.swift`
- Create: `CryptoTrack/Models/Deposit.swift`
- Create: `CryptoTrack/Models/PagedResult.swift`

- [ ] **Step 1: Order 모델 생성**

`CryptoTrack/Models/Order.swift`:
```swift
import Foundation

/// 매수/매도 방향
enum OrderSide: String, Sendable {
    case buy
    case sell
}

/// 체결 완료된 주문을 나타내는 공통 모델
struct Order: Identifiable, Sendable {
    let id: String
    /// 코인 심볼 (예: "BTC", "ETH")
    let symbol: String
    /// 매수/매도
    let side: OrderSide
    /// 체결 단가
    let price: Double
    /// 체결 수량
    let amount: Double
    /// 체결 금액 (price × amount)
    let totalValue: Double
    /// 수수료
    let fee: Double
    /// 출처 거래소
    let exchange: Exchange
    /// 체결 시각
    let executedAt: Date
}
```

- [ ] **Step 2: Deposit 모델 생성**

`CryptoTrack/Models/Deposit.swift`:
```swift
import Foundation

/// 입금 유형
enum DepositType: String, Sendable {
    case crypto
    case fiat
}

/// 입금 상태
enum DepositStatus: String, Sendable {
    case completed
    case pending
    case cancelled
}

/// 입금 내역을 나타내는 공통 모델
struct Deposit: Identifiable, Sendable {
    let id: String
    /// 코인/통화 심볼 (예: "BTC", "KRW")
    let symbol: String
    /// 입금 수량/금액
    let amount: Double
    /// 코인 입금 / 원화 입금
    let type: DepositType
    /// 입금 상태
    let status: DepositStatus
    /// 블록체인 트랜잭션 해시 (코인 입금만)
    let txId: String?
    /// 출처 거래소
    let exchange: Exchange
    /// 완료 시각
    let completedAt: Date
}
```

- [ ] **Step 3: PagedResult 모델 생성**

`CryptoTrack/Models/PagedResult.swift`:
```swift
import Foundation

/// 페이지네이션을 지원하는 결과 래퍼
struct PagedResult<T: Sendable>: Sendable {
    /// 현재 페이지의 항목들
    let items: [T]
    /// 추가 페이지 존재 여부
    let hasMore: Bool
    /// 조회 진행률 (0.0~1.0, 알 수 없으면 nil)
    let progress: Double?
}
```

- [ ] **Step 4: 빌드 확인**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add CryptoTrack/Models/Order.swift CryptoTrack/Models/Deposit.swift CryptoTrack/Models/PagedResult.swift
git commit -m "feat: add Order, Deposit, PagedResult common models"
```

---

### Task 2: ExchangeService 프로토콜 확장

**Files:**
- Modify: `CryptoTrack/Services/Exchange/ExchangeService.swift:30-57`

- [ ] **Step 1: 프로토콜에 fetchOrders, fetchDeposits 추가**

`ExchangeService` 프로토콜 내부, `fetchKlines` 아래에 추가:

```swift
    /// 체결 완료된 주문 내역을 조회합니다.
    /// - Parameters:
    ///   - from: 조회 시작일
    ///   - to: 조회 종료일
    ///   - page: 페이지 번호 (0부터 시작)
    /// - Returns: 페이지 결과 (items + hasMore)
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order>

    /// 입금 내역을 조회합니다.
    /// - Parameters:
    ///   - from: 조회 시작일
    ///   - to: 조회 종료일
    ///   - page: 페이지 번호 (0부터 시작)
    /// - Returns: 페이지 결과 (items + hasMore)
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit>
```

**Note:** 프로토콜에 추가하면 7개 구현체 모두에서 컴파일 에러가 발생한다. Task 3~9에서 각 거래소별로 구현하면 해소된다. 빌드는 모든 거래소 구현이 완료된 후에 확인한다.

- [ ] **Step 2: Commit**

```bash
git add CryptoTrack/Services/Exchange/ExchangeService.swift
git commit -m "feat: add fetchOrders/fetchDeposits to ExchangeService protocol"
```

---

### Task 3: Upbit 체결/입금 구현

**Files:**
- Modify: `CryptoTrack/Services/Exchange/Upbit/UpbitModels.swift`
- Modify: `CryptoTrack/Services/Exchange/Upbit/UpbitService.swift`

- [ ] **Step 1: Upbit 응답 모델 추가**

`UpbitModels.swift` 하단에 추가:

```swift
// MARK: - Order (GET /v1/orders/closed)

/// Upbit 체결 완료 주문 응답 모델
struct UpbitOrder: Decodable, Sendable {
    let uuid: String
    let side: String             // "bid" (매수) or "ask" (매도)
    let market: String           // "KRW-BTC"
    let price: String?           // 지정가 주문 가격
    let avgPrice: String?        // 체결 평균가
    let volume: String           // 주문 수량
    let executedVolume: String   // 체결 수량
    let paidFee: String          // 수수료
    let createdAt: String        // ISO 8601

    enum CodingKeys: String, CodingKey {
        case uuid, side, market, price, volume
        case avgPrice = "avg_price"
        case executedVolume = "executed_volume"
        case paidFee = "paid_fee"
        case createdAt = "created_at"
    }
}

extension UpbitOrder {
    func toOrder() -> Order {
        let symbol = market.split(separator: "-").last.map(String.init) ?? market
        let orderSide: OrderSide = side == "bid" ? .buy : .sell
        let avgPriceValue = Double(avgPrice ?? price ?? "0") ?? 0
        let executedVol = Double(executedVolume) ?? 0
        let feeValue = Double(paidFee) ?? 0

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: createdAt) ?? Date()

        return Order(
            id: "upbit-order-\(uuid)",
            symbol: symbol,
            side: orderSide,
            price: avgPriceValue,
            amount: executedVol,
            totalValue: avgPriceValue * executedVol,
            fee: feeValue,
            exchange: .upbit,
            executedAt: date
        )
    }
}

// MARK: - Deposit (GET /v1/deposits)

/// Upbit 입금 내역 응답 모델
struct UpbitDeposit: Decodable, Sendable {
    let uuid: String
    let currency: String          // "BTC", "KRW"
    let txid: String?
    let state: String             // "accepted", "cancelled", ...
    let amount: String
    let fee: String
    let type: String              // "default" (일반), "internal" (내부)
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case uuid, currency, txid, state, amount, fee, type
        case createdAt = "created_at"
    }
}

extension UpbitDeposit {
    func toDeposit() -> Deposit {
        let depositType: DepositType = (currency == "KRW") ? .fiat : .crypto
        let depositStatus: DepositStatus
        switch state {
        case "accepted": depositStatus = .completed
        case "cancelled", "rejected": depositStatus = .cancelled
        default: depositStatus = .pending
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: createdAt) ?? Date()

        return Deposit(
            id: "upbit-deposit-\(uuid)",
            symbol: currency,
            amount: Double(amount) ?? 0,
            type: depositType,
            status: depositStatus,
            txId: txid,
            exchange: .upbit,
            completedAt: date
        )
    }
}
```

- [ ] **Step 2: UpbitService에 fetchOrders 구현**

`UpbitService.swift`의 `fetchKlines` 메서드 아래에 추가:

```swift
    /// 체결 완료된 주문 내역을 조회합니다.
    /// Upbit API: GET /v1/orders/closed
    /// - 1페이지당 최대 100건
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 100

        var queryItems = [
            URLQueryItem(name: "state", value: "done"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "page", value: "\(page + 1)"),
            URLQueryItem(name: "order_by", value: "desc")
        ]

        let isoFormatter = ISO8601DateFormatter()
        queryItems.append(URLQueryItem(name: "start_time", value: isoFormatter.string(from: from)))
        queryItems.append(URLQueryItem(name: "end_time", value: isoFormatter.string(from: to)))

        // 쿼리 해시 생성
        let queryString = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        let queryHash = queryString.data(using: .utf8).map {
            SHA256.hash(data: $0).compactMap { String(format: "%02x", $0) }.joined()
        }

        let authHeader = try authenticator.generateAuthorizationHeader(queryHash: queryHash)

        guard var components = URLComponents(string: "\(baseURL)/v1/orders/closed") else {
            throw UpbitServiceError.invalidURL
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw UpbitServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as UpbitServiceError {
            throw error
        } catch {
            throw UpbitServiceError.networkError(error)
        }

        do {
            let orders = try JSONDecoder().decode([UpbitOrder].self, from: data)
            return PagedResult(
                items: orders.map { $0.toOrder() },
                hasMore: orders.count >= limit,
                progress: nil
            )
        } catch {
            throw UpbitServiceError.decodingFailed(error)
        }
    }
```

- [ ] **Step 3: UpbitService에 fetchDeposits 구현**

`fetchOrders` 아래에 추가:

```swift
    /// 입금 내역을 조회합니다.
    /// Upbit API: GET /v1/deposits
    /// - 1페이지당 최대 100건
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 100

        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "page", value: "\(page + 1)"),
            URLQueryItem(name: "order_by", value: "desc")
        ]

        let isoFormatter = ISO8601DateFormatter()
        queryItems.append(URLQueryItem(name: "start_time", value: isoFormatter.string(from: from)))
        queryItems.append(URLQueryItem(name: "end_time", value: isoFormatter.string(from: to)))

        let queryString = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        let queryHash = queryString.data(using: .utf8).map {
            SHA256.hash(data: $0).compactMap { String(format: "%02x", $0) }.joined()
        }

        let authHeader = try authenticator.generateAuthorizationHeader(queryHash: queryHash)

        guard var components = URLComponents(string: "\(baseURL)/v1/deposits") else {
            throw UpbitServiceError.invalidURL
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw UpbitServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as UpbitServiceError {
            throw error
        } catch {
            throw UpbitServiceError.networkError(error)
        }

        do {
            let deposits = try JSONDecoder().decode([UpbitDeposit].self, from: data)
            let filtered = deposits
                .map { $0.toDeposit() }
                .filter { $0.completedAt >= from && $0.completedAt <= to }
            return PagedResult(
                items: filtered,
                hasMore: deposits.count >= limit,
                progress: nil
            )
        } catch {
            throw UpbitServiceError.decodingFailed(error)
        }
    }
```

- [ ] **Step 4: Commit**

```bash
git add CryptoTrack/Services/Exchange/Upbit/UpbitModels.swift CryptoTrack/Services/Exchange/Upbit/UpbitService.swift
git commit -m "feat: implement fetchOrders/fetchDeposits for Upbit"
```

---

### Task 4: Binance 체결/입금 구현

**Files:**
- Modify: `CryptoTrack/Services/Exchange/Binance/BinanceModels.swift`
- Modify: `CryptoTrack/Services/Exchange/Binance/BinanceService.swift`

- [ ] **Step 1: Binance 응답 모델 추가**

`BinanceModels.swift` 하단에 추가:

```swift
// MARK: - Trade (GET /api/v3/myTrades)

/// Binance 체결 내역 응답 모델
struct BinanceTrade: Decodable, Sendable {
    let id: Int64
    let symbol: String          // "BTCUSDT"
    let price: String
    let qty: String
    let quoteQty: String        // 체결 금액
    let commission: String      // 수수료
    let commissionAsset: String
    let time: Int64
    let isBuyer: Bool
}

extension BinanceTrade {
    func toOrder(baseSymbol: String) -> Order {
        let side: OrderSide = isBuyer ? .buy : .sell
        let priceValue = Double(price) ?? 0
        let amount = Double(qty) ?? 0
        let total = Double(quoteQty) ?? 0
        let fee = Double(commission) ?? 0

        return Order(
            id: "binance-trade-\(id)",
            symbol: baseSymbol,
            side: side,
            price: priceValue,
            amount: amount,
            totalValue: total,
            fee: fee,
            exchange: .binance,
            executedAt: Date(timeIntervalSince1970: Double(time) / 1000)
        )
    }
}

// MARK: - Deposit (GET /sapi/v1/capital/deposit/hisrec)

/// Binance 입금 내역 응답 모델
struct BinanceDeposit: Decodable, Sendable {
    let id: String
    let coin: String
    let amount: String
    let status: Int             // 0: pending, 6: credited, 1: success
    let txId: String
    let insertTime: Int64

    enum CodingKeys: String, CodingKey {
        case id, coin, amount, status, txId, insertTime
    }
}

extension BinanceDeposit {
    func toDeposit() -> Deposit {
        let depositStatus: DepositStatus
        switch status {
        case 1: depositStatus = .completed
        case 0, 6: depositStatus = .pending
        default: depositStatus = .cancelled
        }

        return Deposit(
            id: "binance-deposit-\(id)",
            symbol: coin,
            amount: Double(amount) ?? 0,
            type: .crypto,
            status: depositStatus,
            txId: txId.isEmpty ? nil : txId,
            exchange: .binance,
            completedAt: Date(timeIntervalSince1970: Double(insertTime) / 1000)
        )
    }
}
```

- [ ] **Step 2: BinanceService에 fetchOrders 구현**

Binance `myTrades`는 심볼 필수이므로, 먼저 보유 자산 심볼 목록을 가져온 뒤 심볼별로 순회한다.

`BinanceService.swift`의 `validateConnection()` 아래에 추가:

```swift
    /// 체결 내역을 조회합니다.
    /// Binance API: GET /api/v3/myTrades (심볼별 조회 필요)
    /// - 1페이지당 최대 1000건. page는 심볼 인덱스로 사용.
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        // 보유 자산 심볼 목록 조회
        let assets = try await fetchAssets()
        let symbols = assets.map { $0.symbol }

        guard page < symbols.count else {
            return PagedResult(items: [], hasMore: false, progress: 1.0)
        }

        let symbol = symbols[page]
        let tradingPair = symbol.uppercased() + "USDT"
        let startTime = Int64(from.timeIntervalSince1970 * 1000)
        let endTime = Int64(to.timeIntervalSince1970 * 1000)

        let queryItems = try authenticator.signedQueryItems(from: [
            URLQueryItem(name: "symbol", value: tradingPair),
            URLQueryItem(name: "startTime", value: "\(startTime)"),
            URLQueryItem(name: "endTime", value: "\(endTime)"),
            URLQueryItem(name: "limit", value: "1000")
        ])

        let request = try buildRequest(
            path: "/api/v3/myTrades",
            queryItems: queryItems,
            requiresAPIKey: true
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let trades = try JSONDecoder().decode([BinanceTrade].self, from: data)
        let orders = trades.map { $0.toOrder(baseSymbol: symbol) }
        let progress = Double(page + 1) / Double(symbols.count)

        return PagedResult(
            items: orders,
            hasMore: page + 1 < symbols.count,
            progress: progress
        )
    }
```

- [ ] **Step 3: BinanceService에 fetchDeposits 구현**

```swift
    /// 입금 내역을 조회합니다.
    /// Binance API: GET /sapi/v1/capital/deposit/hisrec
    /// - 최대 90일 범위. page는 offset으로 사용.
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 1000
        let startTime = Int64(from.timeIntervalSince1970 * 1000)
        let endTime = Int64(to.timeIntervalSince1970 * 1000)

        let queryItems = try authenticator.signedQueryItems(from: [
            URLQueryItem(name: "startTime", value: "\(startTime)"),
            URLQueryItem(name: "endTime", value: "\(endTime)"),
            URLQueryItem(name: "offset", value: "\(page * limit)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ])

        let request = try buildRequest(
            path: "/sapi/v1/capital/deposit/hisrec",
            queryItems: queryItems,
            requiresAPIKey: true
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let deposits = try JSONDecoder().decode([BinanceDeposit].self, from: data)
        return PagedResult(
            items: deposits.map { $0.toDeposit() },
            hasMore: deposits.count >= limit,
            progress: nil
        )
    }
```

- [ ] **Step 4: Commit**

```bash
git add CryptoTrack/Services/Exchange/Binance/BinanceModels.swift CryptoTrack/Services/Exchange/Binance/BinanceService.swift
git commit -m "feat: implement fetchOrders/fetchDeposits for Binance"
```

---

### Task 5: Bithumb 체결/입금 구현

**Files:**
- Modify: `CryptoTrack/Services/Exchange/Bithumb/BithumbModels.swift`
- Modify: `CryptoTrack/Services/Exchange/Bithumb/BithumbService.swift`

- [ ] **Step 1: Bithumb 응답 모델 추가**

`BithumbModels.swift` 하단에 추가:

```swift
// MARK: - Order (POST /info/orders)

/// Bithumb 주문 내역 응답
struct BithumbOrderResponse: Decodable, Sendable {
    let status: String
    let data: [BithumbOrder]?
}

struct BithumbOrder: Decodable, Sendable {
    let orderId: String
    let orderCurrency: String
    let paymentCurrency: String
    let type: String              // "bid" or "ask"
    let price: String
    let units: String
    let fee: String
    let orderDate: String         // 타임스탬프 (마이크로초)

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case orderCurrency = "order_currency"
        case paymentCurrency = "payment_currency"
        case type, price, units, fee
        case orderDate = "order_date"
    }
}

extension BithumbOrder {
    func toOrder() -> Order {
        let side: OrderSide = type == "bid" ? .buy : .sell
        let priceValue = Double(price) ?? 0
        let amount = Double(units) ?? 0
        let feeValue = Double(fee) ?? 0
        // orderDate는 마이크로초 타임스탬프
        let timestamp = Double(orderDate) ?? 0
        let date = Date(timeIntervalSince1970: timestamp / 1_000_000)

        return Order(
            id: "bithumb-order-\(orderId)",
            symbol: orderCurrency,
            side: side,
            price: priceValue,
            amount: amount,
            totalValue: priceValue * amount,
            fee: feeValue,
            exchange: .bithumb,
            executedAt: date
        )
    }
}

// MARK: - Deposit (POST /info/user_transactions, type=4)

/// Bithumb 입금 내역 응답
struct BithumbTransactionResponse: Decodable, Sendable {
    let status: String
    let data: [BithumbTransaction]?
}

struct BithumbTransaction: Decodable, Sendable {
    let transferDate: String       // 타임스탬프
    let units: String
    let currency: String
    let fee: String

    enum CodingKeys: String, CodingKey {
        case transferDate = "transfer_date"
        case units, currency, fee
    }
}

extension BithumbTransaction {
    func toDeposit() -> Deposit {
        let depositType: DepositType = (currency == "KRW") ? .fiat : .crypto
        let timestamp = Double(transferDate) ?? 0
        let date = Date(timeIntervalSince1970: timestamp / 1_000_000)

        return Deposit(
            id: "bithumb-deposit-\(transferDate)-\(currency)",
            symbol: currency,
            amount: Double(units) ?? 0,
            type: depositType,
            status: .completed,
            txId: nil,
            exchange: .bithumb,
            completedAt: date
        )
    }
}
```

- [ ] **Step 2: BithumbService에 fetchOrders/fetchDeposits 구현**

`BithumbService.swift`에 추가. 기존 `fetchAssets` 패턴(POST + authenticator.generateAuthHeaders)을 따른다:

```swift
    /// 체결 내역을 조회합니다.
    /// Bithumb API: POST /info/orders
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 100
        guard let url = URL(string: "\(baseURL)/info/orders") else {
            throw BithumbServiceError.invalidURL
        }

        let parameters: [String: String] = [
            "order_currency": "ALL",
            "payment_currency": "KRW",
            "type": "ALL",
            "count": "\(limit)",
            "after": "\(Int(from.timeIntervalSince1970 * 1_000_000))",
            "offset": "\(page * limit)"
        ]

        let authHeaders = try authenticator.generateAuthHeaders(endpoint: "/info/orders", parameters: parameters)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (field, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        let decoded = try JSONDecoder().decode(BithumbOrderResponse.self, from: data)
        let orders = (decoded.data ?? [])
            .map { $0.toOrder() }
            .filter { $0.executedAt >= from && $0.executedAt <= to }

        return PagedResult(
            items: orders,
            hasMore: (decoded.data?.count ?? 0) >= limit,
            progress: nil
        )
    }

    /// 입금 내역을 조회합니다.
    /// Bithumb API: POST /info/user_transactions (type=4: 입금)
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 100
        guard let url = URL(string: "\(baseURL)/info/user_transactions") else {
            throw BithumbServiceError.invalidURL
        }

        let parameters: [String: String] = [
            "searchGb": "4",
            "count": "\(limit)",
            "offset": "\(page * limit)"
        ]

        let authHeaders = try authenticator.generateAuthHeaders(endpoint: "/info/user_transactions", parameters: parameters)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (field, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        let decoded = try JSONDecoder().decode(BithumbTransactionResponse.self, from: data)
        let deposits = (decoded.data ?? [])
            .map { $0.toDeposit() }
            .filter { $0.completedAt >= from && $0.completedAt <= to }

        return PagedResult(
            items: deposits,
            hasMore: (decoded.data?.count ?? 0) >= limit,
            progress: nil
        )
    }
```

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Services/Exchange/Bithumb/BithumbModels.swift CryptoTrack/Services/Exchange/Bithumb/BithumbService.swift
git commit -m "feat: implement fetchOrders/fetchDeposits for Bithumb"
```

---

### Task 6: Bybit 체결/입금 구현

**Files:**
- Modify: `CryptoTrack/Services/Exchange/Bybit/BybitModels.swift`
- Modify: `CryptoTrack/Services/Exchange/Bybit/BybitService.swift`

- [ ] **Step 1: Bybit 응답 모델 추가**

`BybitModels.swift` 하단에 추가:

```swift
// MARK: - Execution (GET /v5/execution/list)

struct BybitExecutionResult: Decodable, Sendable {
    let list: [BybitExecution]
    let nextPageCursor: String?
}

struct BybitExecution: Decodable, Sendable {
    let execId: String
    let symbol: String          // "BTCUSDT"
    let side: String            // "Buy" or "Sell"
    let execPrice: String
    let execQty: String
    let execValue: String
    let execFee: String
    let execTime: String        // 타임스탬프 (밀리초)
}

extension BybitExecution {
    func toOrder() -> Order {
        let orderSide: OrderSide = side == "Buy" ? .buy : .sell
        // 심볼에서 USDT 제거: "BTCUSDT" → "BTC"
        let baseSymbol = symbol.replacingOccurrences(of: "USDT", with: "")
            .replacingOccurrences(of: "USDC", with: "")

        return Order(
            id: "bybit-exec-\(execId)",
            symbol: baseSymbol,
            side: orderSide,
            price: Double(execPrice) ?? 0,
            amount: Double(execQty) ?? 0,
            totalValue: Double(execValue) ?? 0,
            fee: Double(execFee) ?? 0,
            exchange: .bybit,
            executedAt: Date(timeIntervalSince1970: (Double(execTime) ?? 0) / 1000)
        )
    }
}

// MARK: - Deposit (GET /v5/asset/deposit/query-record)

struct BybitDepositResult: Decodable, Sendable {
    let rows: [BybitDepositRecord]
    let nextPageCursor: String?
}

struct BybitDepositRecord: Decodable, Sendable {
    let id: String?
    let coin: String
    let amount: String
    let status: Int             // 0: unknown, 1: toConfirm, 2: processing, 3: success, 4: failed
    let txID: String
    let successAt: String       // 타임스탬프 (밀리초)
}

extension BybitDepositRecord {
    func toDeposit() -> Deposit {
        let depositStatus: DepositStatus
        switch status {
        case 3: depositStatus = .completed
        case 4: depositStatus = .cancelled
        default: depositStatus = .pending
        }

        return Deposit(
            id: "bybit-deposit-\(id ?? txID)",
            symbol: coin,
            amount: Double(amount) ?? 0,
            type: .crypto,
            status: depositStatus,
            txId: txID.isEmpty ? nil : txID,
            exchange: .bybit,
            completedAt: Date(timeIntervalSince1970: (Double(successAt) ?? 0) / 1000)
        )
    }
}
```

- [ ] **Step 2: BybitService에 fetchOrders/fetchDeposits 구현**

기존 패턴(buildAuthenticatedRequest + BybitResponse 디코딩)을 따른다.

`BybitService.swift`에 추가:

```swift
    /// 체결 내역을 조회합니다.
    /// Bybit API: GET /v5/execution/list
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 100
        let startTime = Int64(from.timeIntervalSince1970 * 1000)
        let endTime = Int64(to.timeIntervalSince1970 * 1000)

        var params = "category=spot&startTime=\(startTime)&endTime=\(endTime)&limit=\(limit)"
        if page > 0, let cursor = lastExecutionCursor {
            params += "&cursor=\(cursor)"
        }

        let request = try buildAuthenticatedRequest(
            path: "/v5/execution/list",
            queryString: params
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(BybitResponse<BybitExecutionResult>.self, from: data)
        try validateRetCode(decoded.retCode, message: decoded.retMsg)

        let result = decoded.result
        lastExecutionCursor = result?.nextPageCursor
        let orders = (result?.list ?? []).map { $0.toOrder() }

        return PagedResult(
            items: orders,
            hasMore: result?.nextPageCursor != nil && !(result?.nextPageCursor?.isEmpty ?? true),
            progress: nil
        )
    }

    /// 입금 내역을 조회합니다.
    /// Bybit API: GET /v5/asset/deposit/query-record
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 100
        let startTime = Int64(from.timeIntervalSince1970 * 1000)
        let endTime = Int64(to.timeIntervalSince1970 * 1000)

        var params = "startTime=\(startTime)&endTime=\(endTime)&limit=\(limit)"
        if page > 0, let cursor = lastDepositCursor {
            params += "&cursor=\(cursor)"
        }

        let request = try buildAuthenticatedRequest(
            path: "/v5/asset/deposit/query-record",
            queryString: params
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(BybitResponse<BybitDepositResult>.self, from: data)
        try validateRetCode(decoded.retCode, message: decoded.retMsg)

        let result = decoded.result
        lastDepositCursor = result?.nextPageCursor
        let deposits = (result?.rows ?? []).map { $0.toDeposit() }

        return PagedResult(
            items: deposits,
            hasMore: result?.nextPageCursor != nil && !(result?.nextPageCursor?.isEmpty ?? true),
            progress: nil
        )
    }
```

**Note:** `BybitService`에 커서 상태 프로퍼티를 추가해야 한다:

```swift
    // 기존 프로퍼티 아래에 추가
    private var lastExecutionCursor: String?
    private var lastDepositCursor: String?
```

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Services/Exchange/Bybit/BybitModels.swift CryptoTrack/Services/Exchange/Bybit/BybitService.swift
git commit -m "feat: implement fetchOrders/fetchDeposits for Bybit"
```

---

### Task 7: Coinone 체결/입금 구현

**Files:**
- Modify: `CryptoTrack/Services/Exchange/Coinone/CoinoneModels.swift`
- Modify: `CryptoTrack/Services/Exchange/Coinone/CoinoneService.swift`

- [ ] **Step 1: Coinone 응답 모델 추가**

`CoinoneModels.swift` 하단에 추가:

```swift
// MARK: - Completed Orders (GET /v2.1/order/completed_orders)

struct CoinoneOrderResponse: Decodable, Sendable {
    let result: String
    let completedOrders: [CoinoneOrder]?

    enum CodingKeys: String, CodingKey {
        case result
        case completedOrders = "completed_orders"
    }
}

struct CoinoneOrder: Decodable, Sendable {
    let orderId: String
    let targetCurrency: String    // "btc", "eth"
    let type: String              // "bid" or "ask"
    let price: String
    let qty: String
    let fee: String
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case targetCurrency = "target_currency"
        case type, price, qty, fee, timestamp
    }
}

extension CoinoneOrder {
    func toOrder() -> Order {
        let side: OrderSide = type == "bid" ? .buy : .sell
        let priceValue = Double(price) ?? 0
        let amount = Double(qty) ?? 0
        let feeValue = Double(fee) ?? 0
        let ts = Double(timestamp) ?? 0

        return Order(
            id: "coinone-order-\(orderId)",
            symbol: targetCurrency.uppercased(),
            side: side,
            price: priceValue,
            amount: amount,
            totalValue: priceValue * amount,
            fee: feeValue,
            exchange: .coinone,
            executedAt: Date(timeIntervalSince1970: ts)
        )
    }
}

// MARK: - Deposit (GET /v2.1/account/deposit)

struct CoinoneDepositResponse: Decodable, Sendable {
    let result: String
    let deposits: [CoinoneDeposit]?
}

struct CoinoneDeposit: Decodable, Sendable {
    let transactionId: String
    let currency: String
    let amount: String
    let status: String           // "success", "pending"
    let txid: String?
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case currency, amount, status, txid, timestamp
    }
}

extension CoinoneDeposit {
    func toDeposit() -> Deposit {
        let depositType: DepositType = (currency.uppercased() == "KRW") ? .fiat : .crypto
        let depositStatus: DepositStatus = (status == "success") ? .completed : .pending
        let ts = Double(timestamp) ?? 0

        return Deposit(
            id: "coinone-deposit-\(transactionId)",
            symbol: currency.uppercased(),
            amount: Double(amount) ?? 0,
            type: depositType,
            status: depositStatus,
            txId: txid,
            exchange: .coinone,
            completedAt: Date(timeIntervalSince1970: ts)
        )
    }
}
```

- [ ] **Step 2: CoinoneService에 fetchOrders/fetchDeposits 구현**

기존 패턴(POST + CoinoneAuthenticator)을 따른다.

`CoinoneService.swift`에 추가:

```swift
    /// 체결 내역을 조회합니다.
    /// Coinone API: GET /v2.1/order/completed_orders
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 100
        guard let url = URL(string: "\(baseURL)/v2.1/order/completed_orders") else {
            throw CoinoneServiceError.invalidURL
        }

        let nonce = "\(Int(Date().timeIntervalSince1970 * 1000))"
        let auth = try authenticator.generateAuth(payload: [
            "nonce": nonce,
            "limit": limit,
            "offset": page * limit
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth.accessToken, forHTTPHeaderField: "X-COINONE-PAYLOAD")
        request.setValue(auth.signature, forHTTPHeaderField: "X-COINONE-SIGNATURE")
        request.httpBody = auth.payload

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        let decoded = try JSONDecoder().decode(CoinoneOrderResponse.self, from: data)
        let orders = (decoded.completedOrders ?? [])
            .map { $0.toOrder() }
            .filter { $0.executedAt >= from && $0.executedAt <= to }

        return PagedResult(
            items: orders,
            hasMore: (decoded.completedOrders?.count ?? 0) >= limit,
            progress: nil
        )
    }

    /// 입금 내역을 조회합니다.
    /// Coinone API: GET /v2.1/account/deposit
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 100
        guard let url = URL(string: "\(baseURL)/v2.1/account/deposit") else {
            throw CoinoneServiceError.invalidURL
        }

        let nonce = "\(Int(Date().timeIntervalSince1970 * 1000))"
        let auth = try authenticator.generateAuth(payload: [
            "nonce": nonce,
            "limit": limit,
            "offset": page * limit
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth.accessToken, forHTTPHeaderField: "X-COINONE-PAYLOAD")
        request.setValue(auth.signature, forHTTPHeaderField: "X-COINONE-SIGNATURE")
        request.httpBody = auth.payload

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        let decoded = try JSONDecoder().decode(CoinoneDepositResponse.self, from: data)
        let deposits = (decoded.deposits ?? [])
            .map { $0.toDeposit() }
            .filter { $0.completedAt >= from && $0.completedAt <= to }

        return PagedResult(
            items: deposits,
            hasMore: (decoded.deposits?.count ?? 0) >= limit,
            progress: nil
        )
    }
```

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Services/Exchange/Coinone/CoinoneModels.swift CryptoTrack/Services/Exchange/Coinone/CoinoneService.swift
git commit -m "feat: implement fetchOrders/fetchDeposits for Coinone"
```

---

### Task 8: Korbit 체결/입금 구현

**Files:**
- Modify: `CryptoTrack/Services/Exchange/Korbit/KorbitModels.swift`
- Modify: `CryptoTrack/Services/Exchange/Korbit/KorbitService.swift`

- [ ] **Step 1: Korbit 응답 모델 추가**

`KorbitModels.swift` 하단에 추가:

```swift
// MARK: - Orders (GET /v1/user/orders)

struct KorbitOrder: Decodable, Sendable {
    let id: Int64
    let currencyPair: String     // "btc_krw"
    let side: String             // "bid" or "ask"
    let avgPrice: String
    let orderAmount: String
    let filledAmount: String
    let fee: String
    let createdAt: Int64         // 타임스탬프 (밀리초)

    enum CodingKeys: String, CodingKey {
        case id
        case currencyPair = "currency_pair"
        case side
        case avgPrice = "avg_price"
        case orderAmount = "order_amount"
        case filledAmount = "filled_amount"
        case fee
        case createdAt = "created_at"
    }
}

extension KorbitOrder {
    func toOrder() -> Order {
        let symbol = currencyPair.split(separator: "_").first.map { String($0).uppercased() } ?? currencyPair
        let orderSide: OrderSide = side == "bid" ? .buy : .sell
        let priceValue = Double(avgPrice) ?? 0
        let amount = Double(filledAmount) ?? 0
        let feeValue = Double(fee) ?? 0

        return Order(
            id: "korbit-order-\(id)",
            symbol: symbol,
            side: orderSide,
            price: priceValue,
            amount: amount,
            totalValue: priceValue * amount,
            fee: feeValue,
            exchange: .korbit,
            executedAt: Date(timeIntervalSince1970: Double(createdAt) / 1000)
        )
    }
}

// MARK: - Transfers (GET /v1/user/transfers)

struct KorbitTransfer: Decodable, Sendable {
    let id: Int64
    let type: String              // "deposit", "withdrawal"
    let currency: String          // "btc", "krw"
    let amount: String
    let completedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id, type, currency, amount
        case completedAt = "completed_at"
    }
}

extension KorbitTransfer {
    func toDeposit() -> Deposit {
        let depositType: DepositType = (currency.uppercased() == "KRW") ? .fiat : .crypto

        return Deposit(
            id: "korbit-deposit-\(id)",
            symbol: currency.uppercased(),
            amount: Double(amount) ?? 0,
            type: depositType,
            status: .completed,
            txId: nil,
            exchange: .korbit,
            completedAt: Date(timeIntervalSince1970: Double(completedAt ?? 0) / 1000)
        )
    }
}
```

- [ ] **Step 2: KorbitService에 fetchOrders/fetchDeposits 구현**

기존 패턴(GET + authenticator.authorizationHeader)을 따른다.

`KorbitService.swift`에 추가:

```swift
    /// 체결 내역을 조회합니다.
    /// Korbit API: GET /v1/user/orders (status=filled)
    /// - 1페이지당 최대 40건
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 40
        let authHeader = try await authenticator.authorizationHeader()

        guard var components = URLComponents(string: "\(baseURL)/v1/user/orders") else {
            throw KorbitServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "status", value: "filled"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(page * limit)")
        ]

        guard let url = components.url else {
            throw KorbitServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as KorbitServiceError {
            throw error
        } catch {
            throw KorbitServiceError.networkError(error)
        }

        let orders = try JSONDecoder().decode([KorbitOrder].self, from: data)
        let filtered = orders
            .map { $0.toOrder() }
            .filter { $0.executedAt >= from && $0.executedAt <= to }

        return PagedResult(
            items: filtered,
            hasMore: orders.count >= limit,
            progress: nil
        )
    }

    /// 입금 내역을 조회합니다.
    /// Korbit API: GET /v1/user/transfers (type=deposit)
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 40
        let authHeader = try await authenticator.authorizationHeader()

        guard var components = URLComponents(string: "\(baseURL)/v1/user/transfers") else {
            throw KorbitServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "type", value: "deposit"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(page * limit)")
        ]

        guard let url = components.url else {
            throw KorbitServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as KorbitServiceError {
            throw error
        } catch {
            throw KorbitServiceError.networkError(error)
        }

        let transfers = try JSONDecoder().decode([KorbitTransfer].self, from: data)
        let deposits = transfers
            .map { $0.toDeposit() }
            .filter { $0.completedAt >= from && $0.completedAt <= to }

        return PagedResult(
            items: deposits,
            hasMore: transfers.count >= limit,
            progress: nil
        )
    }
```

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Services/Exchange/Korbit/KorbitModels.swift CryptoTrack/Services/Exchange/Korbit/KorbitService.swift
git commit -m "feat: implement fetchOrders/fetchDeposits for Korbit"
```

---

### Task 9: OKX 체결/입금 구현

**Files:**
- Modify: `CryptoTrack/Services/Exchange/OKX/OKXModels.swift`
- Modify: `CryptoTrack/Services/Exchange/OKX/OKXService.swift`

- [ ] **Step 1: OKX 응답 모델 추가**

`OKXModels.swift` 하단에 추가:

```swift
// MARK: - Fill (GET /api/v5/trade/fills-history)

struct OKXFill: Decodable, Sendable {
    let tradeId: String
    let instId: String          // "BTC-USDT"
    let side: String            // "buy" or "sell"
    let fillPx: String          // 체결 가격
    let fillSz: String          // 체결 수량
    let fee: String             // 수수료 (음수)
    let ts: String              // 타임스탬프 (밀리초)
}

extension OKXFill {
    func toOrder() -> Order {
        let symbol = instId.split(separator: "-").first.map(String.init) ?? instId
        let orderSide: OrderSide = side == "buy" ? .buy : .sell
        let priceValue = Double(fillPx) ?? 0
        let amount = Double(fillSz) ?? 0
        let feeValue = abs(Double(fee) ?? 0)

        return Order(
            id: "okx-fill-\(tradeId)",
            symbol: symbol,
            side: orderSide,
            price: priceValue,
            amount: amount,
            totalValue: priceValue * amount,
            fee: feeValue,
            exchange: .okx,
            executedAt: Date(timeIntervalSince1970: (Double(ts) ?? 0) / 1000)
        )
    }
}

// MARK: - Deposit (GET /api/v5/asset/deposit-history)

struct OKXDepositRecord: Decodable, Sendable {
    let depId: String
    let ccy: String             // "BTC"
    let amt: String
    let state: String           // "2": success
    let txId: String
    let ts: String              // 타임스탬프 (밀리초)
}

extension OKXDepositRecord {
    func toDeposit() -> Deposit {
        let depositStatus: DepositStatus
        switch state {
        case "2": depositStatus = .completed
        case "0", "1": depositStatus = .pending
        default: depositStatus = .cancelled
        }

        return Deposit(
            id: "okx-deposit-\(depId)",
            symbol: ccy,
            amount: Double(amt) ?? 0,
            type: .crypto,
            status: depositStatus,
            txId: txId.isEmpty ? nil : txId,
            exchange: .okx,
            completedAt: Date(timeIntervalSince1970: (Double(ts) ?? 0) / 1000)
        )
    }
}
```

- [ ] **Step 2: OKXService에 fetchOrders/fetchDeposits 구현**

기존 패턴(buildAuthenticatedRequest + OKXResponse 디코딩)을 따른다.

`OKXService.swift`에 추가:

```swift
    /// 체결 내역을 조회합니다.
    /// OKX API: GET /api/v5/trade/fills-history (최근 3개월)
    /// 3개월 이전: GET /api/v5/trade/fills-history-archive
    func fetchOrders(from: Date, to: Date, page: Int) async throws -> PagedResult<Order> {
        let limit = 100
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()

        // 3개월 이내와 이전을 구분
        let path: String
        if from >= threeMonthsAgo {
            path = "/api/v5/trade/fills-history"
        } else {
            path = "/api/v5/trade/fills-history-archive"
        }

        let beginTs = "\(Int64(from.timeIntervalSince1970 * 1000))"
        let endTs = "\(Int64(to.timeIntervalSince1970 * 1000))"

        var queryItems = [
            URLQueryItem(name: "instType", value: "SPOT"),
            URLQueryItem(name: "begin", value: beginTs),
            URLQueryItem(name: "end", value: endTs),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if page > 0, let cursor = lastOKXFillId {
            queryItems.append(URLQueryItem(name: "after", value: cursor))
        }

        let request = try buildAuthenticatedRequest(method: "GET", path: path, queryItems: queryItems)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OKXResponse<[OKXFill]>.self, from: data)
        guard decoded.isSuccess else {
            throw OKXServiceError.apiError(code: decoded.code, message: decoded.msg)
        }

        let fills = decoded.data.flatMap { $0 }
        lastOKXFillId = fills.last?.tradeId
        let orders = fills.map { $0.toOrder() }

        return PagedResult(
            items: orders,
            hasMore: fills.count >= limit,
            progress: nil
        )
    }

    /// 입금 내역을 조회합니다.
    /// OKX API: GET /api/v5/asset/deposit-history
    func fetchDeposits(from: Date, to: Date, page: Int) async throws -> PagedResult<Deposit> {
        let limit = 100
        let beginTs = "\(Int64(from.timeIntervalSince1970 * 1000))"
        let endTs = "\(Int64(to.timeIntervalSince1970 * 1000))"

        var queryItems = [
            URLQueryItem(name: "begin", value: beginTs),
            URLQueryItem(name: "end", value: endTs),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if page > 0, let cursor = lastOKXDepositId {
            queryItems.append(URLQueryItem(name: "after", value: cursor))
        }

        let request = try buildAuthenticatedRequest(
            method: "GET",
            path: "/api/v5/asset/deposit-history",
            queryItems: queryItems
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OKXResponse<[OKXDepositRecord]>.self, from: data)
        guard decoded.isSuccess else {
            throw OKXServiceError.apiError(code: decoded.code, message: decoded.msg)
        }

        let records = decoded.data.flatMap { $0 }
        lastOKXDepositId = records.last?.depId
        let deposits = records.map { $0.toDeposit() }

        return PagedResult(
            items: deposits,
            hasMore: records.count >= limit,
            progress: nil
        )
    }
```

**Note:** `OKXService`에 커서 상태 프로퍼티를 추가해야 한다:

```swift
    // 기존 프로퍼티 아래에 추가
    private var lastOKXFillId: String?
    private var lastOKXDepositId: String?
```

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Services/Exchange/OKX/OKXModels.swift CryptoTrack/Services/Exchange/OKX/OKXService.swift
git commit -m "feat: implement fetchOrders/fetchDeposits for OKX"
```

---

### Task 10: 빌드 확인 (전체 거래소 구현 완료 후)

- [ ] **Step 1: macOS 빌드**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: iOS 빌드**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_iOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 컴파일 에러가 있으면 수정 후 Commit**

```bash
git add -A
git commit -m "fix: resolve build errors after exchange implementations"
```

---

### Task 11: TransactionHistoryViewModel 구현

**Files:**
- Create: `CryptoTrack/ViewModels/TransactionHistoryViewModel.swift`

- [ ] **Step 1: ViewModel 구현**

`CryptoTrack/ViewModels/TransactionHistoryViewModel.swift`:

```swift
import Foundation
import Observation

/// 거래 내역 탭 종류
enum TransactionTab: String, CaseIterable {
    case orders = "체결 내역"
    case deposits = "입금 내역"
}

/// 거래 내역 화면의 상태와 비즈니스 로직을 관리합니다.
@Observable
@MainActor
final class TransactionHistoryViewModel {

    // MARK: - State

    var selectedTab: TransactionTab = .orders
    var selectedExchange: Exchange? = nil
    var dateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var dateTo: Date = Date()

    var orders: [Order] = []
    var deposits: [Deposit] = []
    var isLoading = false
    var progress: Double = 0.0
    var loadedCount = 0
    var errorMessage: String?

    // MARK: - Private

    private var currentTask: Task<Void, Never>?

    // MARK: - Computed

    /// 날짜별로 그루핑된 체결 내역 (내림차순)
    var groupedOrders: [(Date, [Order])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: orders) { order in
            calendar.startOfDay(for: order.executedAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    /// 날짜별로 그루핑된 입금 내역 (내림차순)
    var groupedDeposits: [(Date, [Deposit])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: deposits) { deposit in
            calendar.startOfDay(for: deposit.completedAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    // MARK: - Actions

    /// 체결 내역을 조회합니다. 기존 조회가 있으면 취소합니다.
    func fetchOrders() {
        cancel()
        orders = []
        loadedCount = 0
        progress = 0.0
        isLoading = true
        errorMessage = nil

        currentTask = Task {
            do {
                let services = targetServices()
                let totalExchanges = services.count

                for (index, service) in services.enumerated() {
                    var page = 0
                    while !Task.isCancelled {
                        let result = try await service.fetchOrders(
                            from: dateFrom,
                            to: dateTo,
                            page: page
                        )
                        orders.append(contentsOf: result.items)
                        loadedCount = orders.count
                        progress = (Double(index) + (result.progress ?? (result.hasMore ? 0.5 : 1.0))) / Double(totalExchanges)

                        if !result.hasMore { break }
                        page += 1
                    }
                }
                progress = 1.0
            } catch is CancellationError {
                // 취소됨 — 무시
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// 입금 내역을 조회합니다. 기존 조회가 있으면 취소합니다.
    func fetchDeposits() {
        cancel()
        deposits = []
        loadedCount = 0
        progress = 0.0
        isLoading = true
        errorMessage = nil

        currentTask = Task {
            do {
                let services = targetServices()
                let totalExchanges = services.count

                for (index, service) in services.enumerated() {
                    var page = 0
                    while !Task.isCancelled {
                        let result = try await service.fetchDeposits(
                            from: dateFrom,
                            to: dateTo,
                            page: page
                        )
                        deposits.append(contentsOf: result.items)
                        loadedCount = deposits.count
                        progress = (Double(index) + (result.progress ?? (result.hasMore ? 0.5 : 1.0))) / Double(totalExchanges)

                        if !result.hasMore { break }
                        page += 1
                    }
                }
                progress = 1.0
            } catch is CancellationError {
                // 취소됨 — 무시
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// 진행 중인 조회를 취소합니다.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Private

    /// 대상 거래소 서비스 목록을 반환합니다.
    private func targetServices() -> [any ExchangeService] {
        let exchanges: [Exchange]
        if let selected = selectedExchange {
            exchanges = [selected]
        } else {
            exchanges = Array(ExchangeManager.shared.registeredExchanges)
        }
        return exchanges.map { makeService(for: $0) }
    }

    /// 거래소에 맞는 ExchangeService 인스턴스를 생성합니다.
    private func makeService(for exchange: Exchange) -> any ExchangeService {
        switch exchange {
        case .upbit: return UpbitService()
        case .binance: return BinanceService()
        case .bithumb: return BithumbService()
        case .bybit: return BybitService()
        case .coinone: return CoinoneService()
        case .korbit: return KorbitService()
        case .okx: return OKXService()
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add CryptoTrack/ViewModels/TransactionHistoryViewModel.swift
git commit -m "feat: add TransactionHistoryViewModel with progressive loading"
```

---

### Task 12: UI 뷰 구현

**Files:**
- Create: `CryptoTrack/Views/TransactionHistory/TransactionHistoryView.swift`
- Create: `CryptoTrack/Views/TransactionHistory/OrderListView.swift`
- Create: `CryptoTrack/Views/TransactionHistory/DepositListView.swift`

- [ ] **Step 1: TransactionHistoryView 구현**

`CryptoTrack/Views/TransactionHistory/TransactionHistoryView.swift`:

```swift
import SwiftUI

/// 거래 내역 메인 화면 (체결/입금 탭 + 필터)
struct TransactionHistoryView: View {
    @State private var viewModel = TransactionHistoryViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                tabContent
            }
            .navigationTitle("거래 내역")
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 12) {
            Picker("탭", selection: $viewModel.selectedTab) {
                ForEach(TransactionTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                exchangePicker
                DatePicker("시작일", selection: $viewModel.dateFrom, displayedComponents: .date)
                    .labelsHidden()
                Text("~")
                DatePicker("종료일", selection: $viewModel.dateTo, displayedComponents: .date)
                    .labelsHidden()

                Button("조회") {
                    if viewModel.selectedTab == .orders {
                        viewModel.fetchOrders()
                    } else {
                        viewModel.fetchDeposits()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var exchangePicker: some View {
        Picker("거래소", selection: $viewModel.selectedExchange) {
            Text("전체").tag(Exchange?.none)
            ForEach(Exchange.allCases, id: \.self) { exchange in
                Text(exchange.rawValue).tag(Exchange?.some(exchange))
            }
        }
        .frame(width: 120)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .orders:
            OrderListView(
                groupedOrders: viewModel.groupedOrders,
                isLoading: viewModel.isLoading,
                progress: viewModel.progress,
                loadedCount: viewModel.loadedCount,
                errorMessage: viewModel.errorMessage
            )
        case .deposits:
            DepositListView(
                groupedDeposits: viewModel.groupedDeposits,
                isLoading: viewModel.isLoading,
                progress: viewModel.progress,
                loadedCount: viewModel.loadedCount,
                errorMessage: viewModel.errorMessage
            )
        }
    }
}

#Preview {
    TransactionHistoryView()
}
```

- [ ] **Step 2: OrderListView 구현**

`CryptoTrack/Views/TransactionHistory/OrderListView.swift`:

```swift
import SwiftUI

/// 체결 내역 리스트 (날짜별 그루핑)
struct OrderListView: View {
    let groupedOrders: [(Date, [Order])]
    let isLoading: Bool
    let progress: Double
    let loadedCount: Int
    let errorMessage: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                errorBanner(error)
            }

            if groupedOrders.isEmpty && !isLoading {
                emptyState
            } else {
                orderList
            }

            if isLoading {
                progressBar
            }
        }
    }

    // MARK: - Subviews

    private var orderList: some View {
        List {
            ForEach(groupedOrders, id: \.0) { date, orders in
                Section(dateFormatter.string(from: date)) {
                    ForEach(orders) { order in
                        orderRow(order)
                    }
                }
            }
        }
    }

    private func orderRow(_ order: Order) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(order.symbol)
                        .font(.body.bold())
                    Text(order.side == .buy ? "매수" : "매도")
                        .font(.caption.bold())
                        .foregroundStyle(order.side == .buy ? .green : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (order.side == .buy ? Color.green : Color.red).opacity(0.1)
                        )
                        .clipShape(Capsule())
                    Spacer()
                    Text(order.exchange.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("\(order.price, specifier: "%.0f")원 × \(order.amount, specifier: "%.8g")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(order.totalValue, specifier: "%.0f")원")
                        .font(.subheadline.bold())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("조회된 체결 내역이 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            ProgressView(value: progress)
            Text("\(Int(progress * 100))% (\(loadedCount)건 로드됨)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }
}
```

- [ ] **Step 3: DepositListView 구현**

`CryptoTrack/Views/TransactionHistory/DepositListView.swift`:

```swift
import SwiftUI

/// 입금 내역 리스트 (날짜별 그루핑)
struct DepositListView: View {
    let groupedDeposits: [(Date, [Deposit])]
    let isLoading: Bool
    let progress: Double
    let loadedCount: Int
    let errorMessage: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                errorBanner(error)
            }

            if groupedDeposits.isEmpty && !isLoading {
                emptyState
            } else {
                depositList
            }

            if isLoading {
                progressBar
            }
        }
    }

    // MARK: - Subviews

    private var depositList: some View {
        List {
            ForEach(groupedDeposits, id: \.0) { date, deposits in
                Section(dateFormatter.string(from: date)) {
                    ForEach(deposits) { deposit in
                        depositRow(deposit)
                    }
                }
            }
        }
    }

    private func depositRow(_ deposit: Deposit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(deposit.symbol)
                        .font(.body.bold())
                    Text(deposit.type == .fiat ? "원화" : "코인")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    Spacer()
                    Text(deposit.exchange.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if deposit.type == .fiat {
                        Text("\(deposit.amount, specifier: "%.0f")원")
                            .font(.subheadline)
                    } else {
                        Text("\(deposit.amount, specifier: "%.8g") \(deposit.symbol)")
                            .font(.subheadline)
                    }
                    Spacer()
                    statusBadge(deposit.status)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func statusBadge(_ status: DepositStatus) -> some View {
        Text(status.displayText)
            .font(.caption)
            .foregroundStyle(status.color)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("조회된 입금 내역이 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            ProgressView(value: progress)
            Text("\(Int(progress * 100))% (\(loadedCount)건 로드됨)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }
}

// MARK: - DepositStatus Helpers

extension DepositStatus {
    var displayText: String {
        switch self {
        case .completed: return "완료"
        case .pending: return "처리중"
        case .cancelled: return "취소"
        }
    }

    var color: Color {
        switch self {
        case .completed: return .green
        case .pending: return .orange
        case .cancelled: return .red
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add CryptoTrack/Views/TransactionHistory/TransactionHistoryView.swift CryptoTrack/Views/TransactionHistory/OrderListView.swift CryptoTrack/Views/TransactionHistory/DepositListView.swift
git commit -m "feat: add TransactionHistory views with order and deposit lists"
```

---

### Task 13: 네비게이션에 거래 내역 메뉴 추가

**Files:**
- Modify: `CryptoTrack/DesignSystem/PlatformAdaptiveLayout.swift`

- [ ] **Step 1: macOS 사이드바에 메뉴 추가**

`PlatformAdaptiveLayout.swift`의 macOS `NavigationSplitView` 사이드바에 "거래 내역" 항목을 추가한다. "대시보드"와 "설정" 사이에 삽입:

```swift
struct AdaptiveRootView: View {
    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List {
                NavigationLink {
                    DashboardView()
                } label: {
                    Label("대시보드", systemImage: "chart.pie.fill")
                }
                NavigationLink {
                    TransactionHistoryView()
                } label: {
                    Label("거래 내역", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("설정", systemImage: "gearshape.fill")
                }
            }
            .navigationTitle("CryptoTrack")
        } detail: {
            DashboardView()
        }
        #else
        TabView {
            DashboardView()
                .tabItem {
                    Label("대시보드", systemImage: "chart.pie.fill")
                }

            TransactionHistoryView()
                .tabItem {
                    Label("거래 내역", systemImage: "clock.arrow.circlepath")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
        }
        #endif
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/DesignSystem/PlatformAdaptiveLayout.swift
git commit -m "feat: add transaction history to sidebar and tab navigation"
```

---

### Task 14: 최종 빌드 확인 및 수정

- [ ] **Step 1: macOS 빌드**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: iOS 빌드**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_iOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 컴파일 에러 수정 후 Commit (필요시)**

```bash
git add -A
git commit -m "fix: resolve remaining build errors for transaction history feature"
```
