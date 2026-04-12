import Foundation

// MARK: - Korbit OAuth Token Response

/// POST /oauth2/access_token 응답 모델
struct KorbitTokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Korbit Balance Response

/// GET /v1/user/balances 응답 모델
/// 응답 형식: {"btc":{"available":"0.5","trade_in_use":"0","withdrawal_in_use":"0","avg_price":"50000000","avg_price_updated_at":...}}
struct KorbitBalance: Decodable, Sendable {
    let available: String
    let tradeInUse: String
    let withdrawalInUse: String
    let avgPrice: String?
    let avgPriceUpdatedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case available
        case tradeInUse = "trade_in_use"
        case withdrawalInUse = "withdrawal_in_use"
        case avgPrice = "avg_price"
        case avgPriceUpdatedAt = "avg_price_updated_at"
    }
}

/// GET /v1/user/balances 전체 응답: 심볼을 키로 하는 딕셔너리
typealias KorbitBalancesResponse = [String: KorbitBalance]

// MARK: - Korbit Ticker Response

/// GET /v1/ticker/detailed 응답 모델
struct KorbitTickerResponse: Decodable, Sendable {
    let last: String
    let open: String?
    let bid: String?
    let ask: String?
    let low: String?
    let high: String?
    let volume: String?
    let change: String?
    let changePercent: String?
    let timestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case last
        case open
        case bid
        case ask
        case low
        case high
        case volume
        case change
        case changePercent = "change_percent"
        case timestamp
    }
}

// MARK: - Order Response (GET /v1/user/orders)

/// Korbit 체결 완료 주문 응답 모델
struct KorbitOrder: Decodable, Sendable {
    let id: Int64
    let currencyPair: String
    let side: String
    let avgPrice: String
    let filledAmount: String
    let fee: String
    let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case currencyPair = "currency_pair"
        case side
        case avgPrice = "avg_price"
        case filledAmount = "filled_amount"
        case fee
        case createdAt = "created_at"
    }
}

// MARK: - Transfer Response (GET /v1/user/transfers)

/// Korbit 입출금 내역 응답 모델
struct KorbitTransfer: Decodable, Sendable {
    let id: Int64
    let type: String
    let currency: String
    let amount: String
    let completedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case currency
        case amount
        case completedAt = "completed_at"
    }
}

// MARK: - Order / Transfer Mapping

extension KorbitOrder {
    /// Korbit 주문 응답을 공통 Order 모델로 변환합니다.
    func toOrder() -> Order {
        // "btc_krw" → "BTC"
        let symbol = currencyPair.split(separator: "_").first.map { $0.uppercased() } ?? currencyPair.uppercased()
        let orderSide: OrderSide = (side == "bid") ? .buy : .sell
        let price = Double(avgPrice) ?? 0
        let amount = Double(filledAmount) ?? 0
        let feeValue = Double(fee) ?? 0
        let date = Date(timeIntervalSince1970: Double(createdAt) / 1000)

        return Order(
            id: "korbit-\(id)",
            symbol: symbol,
            side: orderSide,
            price: price,
            amount: amount,
            totalValue: price * amount,
            fee: feeValue,
            exchange: .korbit,
            executedAt: date
        )
    }
}

extension KorbitTransfer {
    /// Korbit 입출금 응답을 공통 Deposit 모델로 변환합니다.
    func toDeposit() -> Deposit {
        let symbol = currency.uppercased()
        let depositType: DepositType = (symbol == "KRW") ? .fiat : .crypto
        let date: Date
        if let ts = completedAt {
            date = Date(timeIntervalSince1970: Double(ts) / 1000)
        } else {
            date = Date()
        }

        return Deposit(
            id: "korbit-\(id)",
            symbol: symbol,
            amount: Double(amount) ?? 0,
            fee: 0,
            type: depositType,
            status: .completed,
            txId: nil,
            exchange: .korbit,
            completedAt: date
        )
    }
}

// MARK: - Mapping Extensions

extension KorbitBalance {
    /// Korbit 잔고 응답을 공통 Asset 모델로 변환합니다.
    /// - Parameter symbol: 코인 심볼 (예: "btc" → "BTC")
    func toAsset(symbol: String) -> Asset {
        let uppercasedSymbol = symbol.uppercased()
        let balanceValue = Double(available) ?? 0
        let avgPrice = Double(avgPrice ?? "0") ?? 0
        return Asset(
            id: "korbit-\(uppercasedSymbol)",
            symbol: uppercasedSymbol,
            balance: balanceValue,
            averageBuyPrice: avgPrice,
            exchange: .korbit,
            lastUpdated: Date()
        )
    }
}

extension KorbitTickerResponse {
    /// Korbit 시세 응답을 공통 Ticker 모델로 변환합니다.
    /// - Parameter currencyPair: 통화쌍 (예: "btc_krw")
    func toTicker(currencyPair: String) -> Ticker {
        // "btc_krw" → symbol "BTC"
        let symbol = currencyPair.split(separator: "_").first.map { $0.uppercased() } ?? currencyPair.uppercased()
        let currentPrice = Double(last) ?? 0
        let changePercent = Double(changePercent ?? "0") ?? 0
        let volumeValue = Double(volume ?? "0") ?? 0
        let date: Date
        if let ts = timestamp {
            date = Date(timeIntervalSince1970: Double(ts) / 1000)
        } else {
            date = Date()
        }
        return Ticker(
            id: "korbit-\(currencyPair)",
            symbol: symbol,
            currentPrice: currentPrice,
            changeRate24h: changePercent,
            volume24h: volumeValue,
            exchange: .korbit,
            timestamp: date
        )
    }
}
