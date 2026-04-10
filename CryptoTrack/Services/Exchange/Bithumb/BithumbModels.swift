import Foundation

// MARK: - Bithumb API Response Wrapper

/// 빗썸 API 공통 응답 래퍼.
/// 모든 응답은 {"status":"0000","data":{...}} 형식입니다.
struct BithumbResponse<T: Decodable>: Decodable {
    let status: String
    let message: String?
    let data: T?

    /// 정상 응답 여부 (status == "0000")
    var isSuccess: Bool {
        status == "0000"
    }
}

// MARK: - Balance (POST /info/balance)

/// POST /info/balance 응답의 data 필드 모델
struct BithumbBalanceData: Decodable, Sendable {
    let availableKrw: String?
    let totalKrw: String?

    /// 코인별 보유량 및 평균 매수가 (동적 키)
    let currencies: [String: BithumbCurrencyBalance]

    enum CodingKeys: String, CodingKey {
        case availableKrw = "available_krw"
        case totalKrw = "total_krw"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        availableKrw = try container.decodeIfPresent(String.self, forKey: .availableKrw)
        totalKrw = try container.decodeIfPresent(String.self, forKey: .totalKrw)

        // 동적 키에서 available_<symbol>, total_<symbol>, xcoin_last_<symbol> 파싱
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var parsed: [String: BithumbCurrencyBalance] = [:]

        for key in dynamicContainer.allKeys {
            if key.stringValue.hasPrefix("available_") {
                let symbol = String(key.stringValue.dropFirst("available_".count)).uppercased()
                guard symbol != "KRW" else { continue }
                let available = try dynamicContainer.decodeIfPresent(String.self, forKey: key) ?? "0"
                let totalKey = DynamicCodingKey(stringValue: "total_\(symbol.lowercased())")!
                let xcoinKey = DynamicCodingKey(stringValue: "xcoin_last_\(symbol.lowercased())")!
                let total = (try? dynamicContainer.decodeIfPresent(String.self, forKey: totalKey)) ?? available
                let avgBuyPrice = (try? dynamicContainer.decodeIfPresent(String.self, forKey: xcoinKey)) ?? "0"
                parsed[symbol] = BithumbCurrencyBalance(
                    available: available,
                    total: total,
                    avgBuyPrice: avgBuyPrice
                )
            }
        }
        currencies = parsed
    }
}

struct BithumbCurrencyBalance: Sendable {
    let available: String
    let total: String
    let avgBuyPrice: String
}

// MARK: - Ticker (GET /public/ticker/{symbol}_KRW)

/// GET /public/ticker/{symbol}_KRW 응답의 data 필드 모델
struct BithumbTickerData: Decodable, Sendable {
    let closingPrice: String
    let fluctateRate24H: String
    let unitsTraded24H: String
    let date: String?

    enum CodingKeys: String, CodingKey {
        case closingPrice = "closing_price"
        case fluctateRate24H = "fluctate_rate_24H"
        case unitsTraded24H = "units_traded_24H"
        case date
    }
}

// MARK: - Kline (GET /public/candlestick/{symbol}_KRW/{timeframe})

/// 빗썸 캔들스틱 응답 래퍼
struct BithumbCandlestickResponse: Decodable, Sendable {
    let status: String
    let data: [[BithumbCandleValue]]

    var isSuccess: Bool { status == "0000" }
}

/// 빗썸 캔들 배열 내 개별 값 (문자열 또는 숫자 혼합)
enum BithumbCandleValue: Decodable, Sendable {
    case string(String)
    case int(Int64)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int64.self) {
            self = .int(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else {
            self = .string("")
        }
    }

    var doubleValue: Double {
        switch self {
        case .string(let s): return Double(s) ?? 0
        case .int(let i): return Double(i)
        }
    }

    var int64Value: Int64 {
        switch self {
        case .int(let i): return i
        case .string(let s): return Int64(s) ?? 0
        }
    }
}

// MARK: - Order (POST /info/orders)

/// POST /info/orders 응답의 data 필드 모델
struct BithumbOrderData: Decodable, Sendable {
    let orderId: String
    let orderCurrency: String
    let type: String
    let price: String
    let units: String
    let fee: String
    let orderDate: String

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case orderCurrency = "order_currency"
        case type
        case price
        case units
        case fee
        case orderDate = "order_date"
    }
}

// MARK: - Transaction (POST /info/user_transactions)

/// POST /info/user_transactions 응답의 data 필드 모델
struct BithumbTransaction: Decodable, Sendable {
    let transferDate: String
    let units: String
    let currency: String?
    let fee: String

    enum CodingKeys: String, CodingKey {
        case transferDate = "transfer_date"
        case units
        case currency
        case fee
    }
}

// MARK: - Order / Transaction Mapping

extension BithumbOrderData {
    /// 빗썸 주문 응답을 공통 Order 모델로 변환합니다.
    func toOrder() -> Order {
        let orderSide: OrderSide = (type == "bid") ? .buy : .sell
        let priceValue = Double(price) ?? 0
        let unitsValue = Double(units) ?? 0
        let feeValue = Double(fee) ?? 0

        // orderDate는 마이크로초 타임스탬프입니다
        let microseconds = Double(orderDate) ?? 0
        let date = Date(timeIntervalSince1970: microseconds / 1_000_000)

        return Order(
            id: "bithumb-\(orderId)",
            symbol: orderCurrency,
            side: orderSide,
            price: priceValue,
            amount: unitsValue,
            totalValue: priceValue * unitsValue,
            fee: feeValue,
            exchange: .bithumb,
            executedAt: date
        )
    }
}

extension BithumbTransaction {
    /// 빗썸 거래 내역을 공통 Deposit 모델로 변환합니다.
    func toDeposit() -> Deposit {
        let symbol = (currency ?? "KRW").uppercased()
        let depositType: DepositType = (symbol == "KRW") ? .fiat : .crypto

        // transferDate는 마이크로초 타임스탬프입니다
        let microseconds = Double(transferDate) ?? 0
        let date = Date(timeIntervalSince1970: microseconds / 1_000_000)

        return Deposit(
            id: "bithumb-\(transferDate)",
            symbol: symbol,
            amount: Double(units) ?? 0,
            type: depositType,
            status: .completed,
            txId: nil,
            exchange: .bithumb,
            completedAt: date
        )
    }
}

// MARK: - Dynamic Coding Key Helper

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

// MARK: - Mapping Extensions

extension BithumbCurrencyBalance {
    /// 빗썸 코인 잔고를 공통 Asset 모델로 변환합니다.
    func toAsset(symbol: String) -> Asset {
        let balanceValue = Double(available) ?? 0
        let avgPrice = Double(avgBuyPrice) ?? 0
        return Asset(
            id: "bithumb-\(symbol)",
            symbol: symbol,
            balance: balanceValue,
            averageBuyPrice: avgPrice,
            exchange: .bithumb,
            lastUpdated: Date()
        )
    }
}

extension BithumbCandleValue {
    /// 빗썸 캔들 배열 [timestamp, open, close, high, low, volume]을 Kline으로 변환합니다.
    static func toKline(from row: [BithumbCandleValue], symbol: String, timeframe: ChartTimeframe) -> Kline? {
        guard row.count >= 6 else { return nil }
        let ts = row[0].int64Value
        let open = row[1].doubleValue
        let close = row[2].doubleValue
        let high = row[3].doubleValue
        let low = row[4].doubleValue
        let volume = row[5].doubleValue
        return Kline(
            id: "bithumb-\(symbol)-\(ts)",
            timestamp: Date(timeIntervalSince1970: Double(ts) / 1000),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            timeframe: timeframe,
            exchange: .bithumb,
            symbol: symbol
        )
    }
}

extension BithumbTickerData {
    /// 빗썸 시세 응답을 공통 Ticker 모델로 변환합니다.
    func toTicker(symbol: String) -> Ticker {
        let price = Double(closingPrice) ?? 0
        let changeRate = Double(fluctateRate24H) ?? 0
        let volume = Double(unitsTraded24H) ?? 0
        let timestamp: Date
        if let dateStr = date, let ms = Double(dateStr) {
            timestamp = Date(timeIntervalSince1970: ms / 1000)
        } else {
            timestamp = Date()
        }
        return Ticker(
            id: "bithumb-\(symbol)",
            symbol: symbol,
            currentPrice: price,
            changeRate24h: changeRate,
            volume24h: volume,
            exchange: .bithumb,
            timestamp: timestamp
        )
    }
}
