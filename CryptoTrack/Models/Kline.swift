import Foundation

/// 차트 타임프레임 (봉 간격)
enum ChartTimeframe: String, CaseIterable, Sendable {
    case minute1 = "1m"
    case minute5 = "5m"
    case minute15 = "15m"
    case hour1 = "1h"
    case hour4 = "4h"
    case day1 = "1d"
    case week1 = "1w"
    case month1 = "1M"

    var displayName: String {
        switch self {
        case .minute1: "1분"
        case .minute5: "5분"
        case .minute15: "15분"
        case .hour1: "1시간"
        case .hour4: "4시간"
        case .day1: "1일"
        case .week1: "1주"
        case .month1: "1개월"
        }
    }
}

/// OHLCV 캔들스틱 데이터 모델
struct Kline: Identifiable, Sendable {
    let id: String
    /// 캔들 시작 시각
    let timestamp: Date
    /// 시가
    let open: Double
    /// 고가
    let high: Double
    /// 저가
    let low: Double
    /// 종가
    let close: Double
    /// 거래량
    let volume: Double
    /// 타임프레임
    let timeframe: ChartTimeframe
    /// 데이터 출처 거래소
    let exchange: Exchange
    /// 심볼
    let symbol: String

    /// 양봉 여부
    var isBullish: Bool { close >= open }
}
