import Foundation

enum DepositType: String, Sendable {
    case crypto
    case fiat
}

enum DepositStatus: String, Sendable {
    case completed
    case pending
    case cancelled
}

struct Deposit: Identifiable, Sendable {
    let id: String
    let symbol: String
    let amount: Double
    let fee: Double
    let type: DepositType
    let status: DepositStatus
    let txId: String?
    let exchange: Exchange
    let completedAt: Date
}
