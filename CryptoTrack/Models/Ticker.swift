import Foundation

/// 거래소 응답을 통합하는 공통 시세 모델
struct Ticker: Identifiable, Sendable {
    let id: String
    /// 코인 심볼
    let symbol: String
    /// 현재가
    let currentPrice: Double
    /// 24시간 변동률 (%)
    let changeRate24h: Double
    /// 24시간 거래량
    let volume24h: Double
    /// 시세 출처 거래소
    let exchange: Exchange
    /// 조회 시각
    let timestamp: Date
}
