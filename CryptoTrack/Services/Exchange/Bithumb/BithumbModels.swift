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
