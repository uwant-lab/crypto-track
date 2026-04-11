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
