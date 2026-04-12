import Foundation

// MARK: - Coinone API Response Models

/// POST /v2.1/account/balance 응답 모델
struct CoinoneBalanceResponse: Decodable, Sendable {
    let result: String
    let errorCode: String?
    let balances: [CoinoneBalance]?

    enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case balances
    }
}

/// 개별 자산 잔액 모델
struct CoinoneBalance: Decodable, Sendable {
    let currency: String
    let balance: String
    let available: String
    let limitOrder: String
    let avgPrice: String

    enum CodingKeys: String, CodingKey {
        case currency
        case balance
        case available
        case limitOrder = "limit_order"
        case avgPrice = "avg_price"
    }
}

/// GET /public/v2/ticker_new/KRW/{symbol} 응답 모델
struct CoinoneTickerResponse: Decodable, Sendable {
    let result: String
    let errorCode: String?
    let tickers: [CoinoneTicker]?

    enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case tickers
    }
}

/// 개별 시세 모델
struct CoinoneTicker: Decodable, Sendable {
    let targetCurrency: String
    let last: String
    let yesterdayLast: String?
    let volume: String
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case targetCurrency = "target_currency"
        case last
        case yesterdayLast = "yesterday_last"
        case volume
        case timestamp
    }
}

// MARK: - Kline Response

/// Coinone GET /public/v2/chart/KRW/{symbol} 응답 모델
struct CoinoneChartResponse: Decodable, Sendable {
    let result: String
    let errorCode: String?
    let chart: [CoinoneCandle]?

    enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case chart
    }
}

struct CoinoneCandle: Decodable, Sendable {
    let timestamp: String
    let open: String
    let high: String
    let low: String
    let close: String
    let targetVolume: String

    enum CodingKeys: String, CodingKey {
        case timestamp
        case open
        case high
        case low
        case close
        case targetVolume = "target_volume"
    }
}

extension CoinoneCandle {
    func toKline(symbol: String, timeframe: ChartTimeframe) -> Kline {
        let ts = Double(timestamp) ?? 0
        return Kline(
            id: "coinone-\(symbol)-\(timestamp)",
            timestamp: Date(timeIntervalSince1970: ts / 1000),
            open: Double(open) ?? 0,
            high: Double(high) ?? 0,
            low: Double(low) ?? 0,
            close: Double(close) ?? 0,
            volume: Double(targetVolume) ?? 0,
            timeframe: timeframe,
            exchange: .coinone,
            symbol: symbol
        )
    }
}

// MARK: - Order Response (GET /v2.1/order/completed_orders)

/// Coinone 체결 완료 주문 응답 모델
struct CoinoneOrderResponse: Decodable, Sendable {
    let result: String
    let errorCode: String?
    let completedOrders: [CoinoneOrder]?

    enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case completedOrders = "completed_orders"
    }
}

/// Coinone 체결 주문 모델
struct CoinoneOrder: Decodable, Sendable {
    let orderId: String
    let targetCurrency: String
    let type: String
    let price: String
    let qty: String
    let fee: String
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case targetCurrency = "target_currency"
        case type
        case price
        case qty
        case fee
        case timestamp
    }
}

// MARK: - Deposit Response (GET /v2.1/account/deposit)

/// Coinone 입금 내역 응답 모델
struct CoinoneDepositResponse: Decodable, Sendable {
    let result: String
    let errorCode: String?
    let deposits: [CoinoneDeposit]?

    enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case deposits
    }
}

/// Coinone 입금 내역 모델
struct CoinoneDeposit: Decodable, Sendable {
    let transactionId: String
    let currency: String
    let amount: String
    let status: String
    let txid: String?
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case currency
        case amount
        case status
        case txid
        case timestamp
    }
}

// MARK: - Order / Deposit Mapping

extension CoinoneOrder {
    /// Coinone 주문 응답을 공통 Order 모델로 변환합니다.
    func toOrder() -> Order {
        let orderSide: OrderSide = (type == "bid") ? .buy : .sell
        let priceValue = Double(price) ?? 0
        let qtyValue = Double(qty) ?? 0
        let feeValue = Double(fee) ?? 0
        let ts = Double(timestamp) ?? 0
        let date = Date(timeIntervalSince1970: ts)

        return Order(
            id: "coinone-\(orderId)",
            symbol: targetCurrency.uppercased(),
            side: orderSide,
            price: priceValue,
            amount: qtyValue,
            totalValue: priceValue * qtyValue,
            fee: feeValue,
            exchange: .coinone,
            executedAt: date
        )
    }
}

extension CoinoneDeposit {
    /// Coinone 입금 응답을 공통 Deposit 모델로 변환합니다.
    func toDeposit() -> Deposit {
        let symbol = currency.uppercased()
        let depositType: DepositType = (symbol == "KRW") ? .fiat : .crypto
        let depositStatus: DepositStatus
        switch status {
        case "completed":
            depositStatus = .completed
        case "cancelled":
            depositStatus = .cancelled
        default:
            depositStatus = .pending
        }
        let ts = Double(timestamp) ?? 0
        let date = Date(timeIntervalSince1970: ts)

        return Deposit(
            id: "coinone-\(transactionId)",
            symbol: symbol,
            amount: Double(amount) ?? 0,
            fee: 0,
            type: depositType,
            status: depositStatus,
            txId: txid,
            exchange: .coinone,
            completedAt: date
        )
    }
}

// MARK: - Mapping Extensions

extension CoinoneBalance {
    /// Coinone 잔액 응답을 공통 Asset 모델로 변환합니다.
    func toAsset() -> Asset {
        let balanceValue = Double(balance) ?? 0
        let avgPrice = Double(avgPrice) ?? 0
        return Asset(
            id: "coinone-\(currency)",
            symbol: currency,
            balance: balanceValue,
            averageBuyPrice: avgPrice,
            exchange: .coinone,
            lastUpdated: Date()
        )
    }
}

extension CoinoneTicker {
    /// Coinone 시세 응답을 공통 Ticker 모델로 변환합니다.
    func toTicker() -> Ticker {
        let currentPrice = Double(last) ?? 0
        let prevClose = Double(yesterdayLast ?? "0") ?? 0
        let changeRate: Double
        if prevClose > 0 {
            changeRate = ((currentPrice - prevClose) / prevClose) * 100
        } else {
            changeRate = 0
        }
        let vol = Double(volume) ?? 0
        let ts = Double(timestamp) ?? 0
        let date = ts > 0 ? Date(timeIntervalSince1970: ts / 1000) : Date()

        return Ticker(
            id: "coinone-\(targetCurrency)",
            symbol: targetCurrency,
            currentPrice: currentPrice,
            changeRate24h: changeRate,
            volume24h: vol,
            exchange: .coinone,
            timestamp: date
        )
    }
}
