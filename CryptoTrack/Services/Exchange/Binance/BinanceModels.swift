import Foundation

// MARK: - Account Response

/// Binance GET /api/v3/account 응답 모델
struct BinanceAccountResponse: Decodable {
    let balances: [BinanceBalance]
}

struct BinanceBalance: Decodable {
    let asset: String
    let free: String
    let locked: String

    /// 실제 보유 수량 (free + locked)
    var totalBalance: Double {
        (Double(free) ?? 0) + (Double(locked) ?? 0)
    }
}

// MARK: - Ticker Response

/// Binance GET /api/v3/ticker/24hr 응답 모델
struct BinanceTicker: Decodable {
    let symbol: String
    let lastPrice: String
    let priceChangePercent: String
    let volume: String
}

// MARK: - Kline Response

/// Binance GET /api/v3/klines 응답 파서
/// 응답 형식: [[openTime, open, high, low, close, volume, ...], ...]
struct BinanceKline: Sendable {
    let openTime: Int64
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

extension BinanceKline {
    /// Binance kline 배열 응답을 파싱합니다.
    static func parse(from array: [JSONValue]) -> BinanceKline? {
        guard array.count >= 6,
              case .int(let openTime) = array[0],
              case .string(let openStr) = array[1],
              case .string(let highStr) = array[2],
              case .string(let lowStr) = array[3],
              case .string(let closeStr) = array[4],
              case .string(let volStr) = array[5]
        else { return nil }
        return BinanceKline(
            openTime: openTime,
            open: Double(openStr) ?? 0,
            high: Double(highStr) ?? 0,
            low: Double(lowStr) ?? 0,
            close: Double(closeStr) ?? 0,
            volume: Double(volStr) ?? 0
        )
    }

    func toKline(symbol: String, timeframe: ChartTimeframe) -> Kline {
        Kline(
            id: "binance-\(symbol)-\(openTime)",
            timestamp: Date(timeIntervalSince1970: Double(openTime) / 1000),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            timeframe: timeframe,
            exchange: .binance,
            symbol: symbol
        )
    }
}

/// JSON 값 파싱을 위한 헬퍼 열거형
enum JSONValue: Decodable {
    case string(String)
    case int(Int64)
    case double(Double)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode(Int64.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else {
            self = .null
        }
    }
}

// MARK: - Mapping Extensions

extension BinanceBalance {
    /// BinanceBalance → 공통 Asset 모델로 변환
    func toAsset() -> Asset {
        Asset(
            id: "binance-\(asset.lowercased())",
            symbol: asset,
            balance: totalBalance,
            averageBuyPrice: 0,
            exchange: .binance,
            lastUpdated: Date()
        )
    }
}

extension BinanceTicker {
    /// BinanceTicker → 공통 Ticker 모델로 변환
    /// - Parameter baseSymbol: 거래 쌍에서 기반 코인 심볼 추출 (예: "BTCUSDT" → "BTC")
    func toTicker(baseSymbol: String) -> Ticker {
        Ticker(
            id: "binance-\(symbol.lowercased())",
            symbol: baseSymbol,
            currentPrice: Double(lastPrice) ?? 0,
            changeRate24h: Double(priceChangePercent) ?? 0,
            volume24h: Double(volume) ?? 0,
            exchange: .binance,
            timestamp: Date()
        )
    }
}
