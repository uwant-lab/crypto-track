import Foundation

// MARK: - Upbit API Response Models

/// GET /v1/accounts 응답 모델
struct UpbitAccount: Decodable, Sendable {
    let currency: String
    let balance: String
    let locked: String
    let avgBuyPrice: String
    let avgBuyPriceModified: Bool
    let unitCurrency: String

    enum CodingKeys: String, CodingKey {
        case currency
        case balance
        case locked
        case avgBuyPrice = "avg_buy_price"
        case avgBuyPriceModified = "avg_buy_price_modified"
        case unitCurrency = "unit_currency"
    }
}

/// GET /v1/ticker 응답 모델
struct UpbitTicker: Decodable, Sendable {
    let market: String
    let tradePrice: Double
    let signedChangeRate: Double
    let accTradeVolume24h: Double
    let timestamp: Int64

    enum CodingKeys: String, CodingKey {
        case market
        case tradePrice = "trade_price"
        case signedChangeRate = "signed_change_rate"
        case accTradeVolume24h = "acc_trade_volume_24h"
        case timestamp
    }
}

// MARK: - Kline (GET /v1/candles/...)

/// Upbit 캔들스틱 응답 모델
struct UpbitKline: Decodable, Sendable {
    let candleDateTimeKst: String
    let openingPrice: Double
    let highPrice: Double
    let lowPrice: Double
    let tradePrice: Double
    let candleAccTradeVolume: Double
    let timestamp: Int64

    enum CodingKeys: String, CodingKey {
        case candleDateTimeKst = "candle_date_time_kst"
        case openingPrice = "opening_price"
        case highPrice = "high_price"
        case lowPrice = "low_price"
        case tradePrice = "trade_price"
        case candleAccTradeVolume = "candle_acc_trade_volume"
        case timestamp
    }
}

// MARK: - Mapping Extensions

extension UpbitAccount {
    /// Upbit 계좌 응답을 공통 Asset 모델로 변환합니다.
    func toAsset() -> Asset {
        let balanceValue = (Double(balance) ?? 0) + (Double(locked) ?? 0)
        let avgPrice = Double(avgBuyPrice) ?? 0
        return Asset(
            id: "upbit-\(currency)",
            symbol: currency,
            balance: balanceValue,
            averageBuyPrice: avgPrice,
            avgBuyPriceModified: avgBuyPriceModified,
            exchange: .upbit,
            lastUpdated: Date()
        )
    }
}

extension UpbitTicker {
    /// Upbit 시세 응답을 공통 Ticker 모델로 변환합니다.
    func toTicker() -> Ticker {
        // market 형식: "KRW-BTC" → symbol: "BTC"
        let symbol = market.split(separator: "-").last.map(String.init) ?? market
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        return Ticker(
            id: "upbit-\(market)",
            symbol: symbol,
            currentPrice: tradePrice,
            changeRate24h: signedChangeRate * 100,
            volume24h: accTradeVolume24h,
            exchange: .upbit,
            timestamp: date
        )
    }
}

// MARK: - Order (GET /v1/orders/closed)

/// Upbit 체결 완료 주문 응답 모델
struct UpbitOrder: Decodable, Sendable {
    let uuid: String
    let side: String
    let market: String
    let ordType: String?
    let price: String?
    let avgPrice: String?
    let volume: String?
    let executedVolume: String
    let executedFunds: String?
    let paidFee: String
    let tradesCount: Int?
    let createdAt: String
    let trades: [UpbitTrade]?

    enum CodingKeys: String, CodingKey {
        case uuid
        case side
        case market
        case ordType = "ord_type"
        case price
        case avgPrice = "avg_price"
        case volume
        case executedVolume = "executed_volume"
        case executedFunds = "executed_funds"
        case paidFee = "paid_fee"
        case tradesCount = "trades_count"
        case createdAt = "created_at"
        case trades
    }
}

/// Upbit 체결 상세 정보
struct UpbitTrade: Decodable, Sendable {
    let market: String
    let uuid: String
    let price: String
    let volume: String
    let funds: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case market
        case uuid
        case price
        case volume
        case funds
        case createdAt = "created_at"
    }
}

// MARK: - Deposit (GET /v1/deposits)

/// Upbit 입금 내역 응답 모델
struct UpbitDeposit: Decodable, Sendable {
    let uuid: String
    let currency: String
    let txid: String?
    let state: String
    let amount: String
    let fee: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case uuid
        case currency
        case txid
        case state
        case amount
        case fee
        case createdAt = "created_at"
    }
}

// MARK: - Order / Deposit Mapping

extension UpbitOrder {
    /// Upbit 주문 응답을 공통 Order 모델로 변환합니다.
    func toOrder() -> Order {
        // market 형식: "KRW-BTC" → symbol: "BTC"
        let symbol = market.split(separator: "-").last.map(String.init) ?? market
        let orderSide: OrderSide = (side == "bid") ? .buy : .sell
        let execVolume = Double(executedVolume) ?? 0
        let fee = Double(paidFee) ?? 0

        // 체결 금액: executed_funds → avg_price × volume → price × volume
        let funds = Double(executedFunds ?? "") ?? 0
        let avg = Double(avgPrice ?? "") ?? 0
        let limitPrice = Double(price ?? "") ?? 0

        let total: Double
        let unitPrice: Double
        if funds > 0 {
            total = funds
            unitPrice = execVolume > 0 ? funds / execVolume : avg
        } else if avg > 0 {
            unitPrice = avg
            total = avg * execVolume
        } else {
            unitPrice = limitPrice
            total = limitPrice * execVolume
        }

        // 체결 시각: trades 배열의 마지막 체결 시각 → 주문 생성 시각 폴백
        let dateString = trades?.last?.createdAt ?? createdAt
        let date = Self.parseDate(dateString)

        return Order(
            id: "upbit-\(uuid)",
            symbol: symbol,
            side: orderSide,
            price: unitPrice,
            amount: execVolume,
            totalValue: total,
            fee: fee,
            exchange: .upbit,
            executedAt: date
        )
    }

    /// ISO 8601 날짜 파싱 (fractional seconds 유무 모두 처리)
    private static func parseDate(_ string: String) -> Date {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFrac.date(from: string) { return date }

        let withoutFrac = ISO8601DateFormatter()
        withoutFrac.formatOptions = [.withInternetDateTime]
        return withoutFrac.date(from: string) ?? Date()
    }
}

extension UpbitDeposit {
    /// Upbit 입금 응답을 공통 Deposit 모델로 변환합니다.
    func toDeposit() -> Deposit {
        let depositType: DepositType = (currency == "KRW") ? .fiat : .crypto
        let depositStatus: DepositStatus
        switch state {
        case "ACCEPTED":
            depositStatus = .completed
        case "CANCELLED", "REJECTED":
            depositStatus = .cancelled
        default:
            depositStatus = .pending
        }

        let date = Self.parseDate(createdAt)

        return Deposit(
            id: "upbit-\(uuid)",
            symbol: currency,
            amount: Double(amount) ?? 0,
            fee: Double(fee) ?? 0,
            type: depositType,
            status: depositStatus,
            txId: txid,
            exchange: .upbit,
            completedAt: date
        )
    }

    /// ISO 8601 날짜 파싱 (fractional seconds 유무 모두 처리)
    private static func parseDate(_ string: String) -> Date {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFrac.date(from: string) { return date }

        let withoutFrac = ISO8601DateFormatter()
        withoutFrac.formatOptions = [.withInternetDateTime]
        return withoutFrac.date(from: string) ?? Date()
    }
}

extension UpbitKline {
    /// Upbit 캔들 응답을 공통 Kline 모델로 변환합니다.
    func toKline(symbol: String, timeframe: ChartTimeframe) -> Kline {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        return Kline(
            id: "upbit-\(symbol)-\(timestamp)",
            timestamp: date,
            open: openingPrice,
            high: highPrice,
            low: lowPrice,
            close: tradePrice,
            volume: candleAccTradeVolume,
            timeframe: timeframe,
            exchange: .upbit,
            symbol: symbol
        )
    }
}
