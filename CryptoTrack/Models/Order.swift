import Foundation

/// 매수/매도 방향
enum OrderSide: String, Sendable {
    case buy
    case sell
}

/// 체결 완료된 주문을 나타내는 공통 모델
struct Order: Identifiable, Sendable {
    let id: String
    let symbol: String
    let side: OrderSide
    let price: Double
    let amount: Double
    let totalValue: Double
    let fee: Double
    let exchange: Exchange
    let executedAt: Date
}
