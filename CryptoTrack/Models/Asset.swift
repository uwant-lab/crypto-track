import Foundation

/// 거래소 응답을 통합하는 공통 자산 모델
struct Asset: Identifiable, Sendable {
    let id: String
    /// 코인 심볼 (예: "BTC", "ETH")
    let symbol: String
    /// 보유 수량
    let balance: Double
    /// 평균 매수 단가 (KRW 또는 USDT)
    let averageBuyPrice: Double
    /// 자산이 속한 거래소
    let exchange: Exchange
    /// 마지막 동기화 시각
    let lastUpdated: Date

    /// 총 매수 금액
    var totalCost: Double {
        balance * averageBuyPrice
    }
}
