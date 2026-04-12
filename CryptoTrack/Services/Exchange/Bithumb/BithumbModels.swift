import Foundation

// MARK: - Bithumb v1 API Response Models
// 빗썸 v1 API는 Upbit과 동일한 구조를 사용합니다.

/// GET /v1/accounts 응답 모델 (Upbit과 동일)
struct BithumbAccount: Decodable, Sendable {
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

/// GET /v1/ticker 응답 모델 (Upbit과 동일)
struct BithumbTicker: Decodable, Sendable {
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

/// 빗썸 캔들스틱 응답 모델 (Upbit과 동일)
struct BithumbKline: Decodable, Sendable {
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

// MARK: - Order (GET /v1/orders)

/// 빗썸 주문 응답 모델 (GET /v1/orders, GET /v1/order)
struct BithumbOrder: Decodable, Sendable {
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
    let trades: [BithumbTrade]?

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

/// 빗썸 체결 상세 정보 (trades 배열 내 항목)
struct BithumbTrade: Decodable, Sendable {
    let market: String
    let uuid: String
    let price: String
    let volume: String
    let funds: String
    let side: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case market
        case uuid
        case price
        case volume
        case funds
        case side
        case createdAt = "created_at"
    }
}

// MARK: - Deposit (GET /v1/deposits)

/// 빗썸 입금 내역 응답 모델 (Upbit과 동일)
struct BithumbDeposit: Decodable, Sendable {
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

// MARK: - Mapping Extensions

extension BithumbAccount {
    /// 빗썸 계좌 응답을 공통 Asset 모델로 변환합니다.
    func toAsset() -> Asset {
        let balanceValue = (Double(balance) ?? 0) + (Double(locked) ?? 0)
        let avgPrice = Double(avgBuyPrice) ?? 0
        return Asset(
            id: "bithumb-\(currency)",
            symbol: currency,
            balance: balanceValue,
            averageBuyPrice: avgPrice,
            avgBuyPriceModified: avgBuyPriceModified,
            exchange: .bithumb,
            lastUpdated: Date()
        )
    }
}

extension BithumbTicker {
    /// 빗썸 시세 응답을 공통 Ticker 모델로 변환합니다.
    func toTicker() -> Ticker {
        // market 형식: "KRW-BTC" → symbol: "BTC"
        let symbol = market.split(separator: "-").last.map(String.init) ?? market
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        return Ticker(
            id: "bithumb-\(market)",
            symbol: symbol,
            currentPrice: tradePrice,
            changeRate24h: signedChangeRate * 100,
            volume24h: accTradeVolume24h,
            exchange: .bithumb,
            timestamp: date
        )
    }
}

extension BithumbKline {
    /// 빗썸 캔들 응답을 공통 Kline 모델로 변환합니다.
    func toKline(symbol: String, timeframe: ChartTimeframe) -> Kline {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        return Kline(
            id: "bithumb-\(symbol)-\(timestamp)",
            timestamp: date,
            open: openingPrice,
            high: highPrice,
            low: lowPrice,
            close: tradePrice,
            volume: candleAccTradeVolume,
            timeframe: timeframe,
            exchange: .bithumb,
            symbol: symbol
        )
    }
}

extension BithumbOrder {
    /// 빗썸 주문 응답을 공통 Order 모델로 변환합니다.
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
            id: "bithumb-\(uuid)",
            symbol: symbol,
            side: orderSide,
            price: unitPrice,
            amount: execVolume,
            totalValue: total,
            fee: fee,
            exchange: .bithumb,
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
        if let date = withoutFrac.date(from: string) { return date }

        return Date()
    }
}

extension BithumbDeposit {
    /// 빗썸 입금 응답을 공통 Deposit 모델로 변환합니다.
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

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: createdAt) ?? Date()

        return Deposit(
            id: "bithumb-\(uuid)",
            symbol: currency,
            amount: Double(amount) ?? 0,
            type: depositType,
            status: depositStatus,
            txId: txid,
            exchange: .bithumb,
            completedAt: date
        )
    }
}
