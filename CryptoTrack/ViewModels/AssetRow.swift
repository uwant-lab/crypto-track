import Foundation

/// 자산 + 시세를 평탄화한 표시용 행 모델.
/// SwiftUI Table의 KeyPathComparator는 단순 KeyPath만 지원하므로,
/// ticker가 있어야 계산 가능한 값(currentPrice/currentValue/profitRate)을
/// 미리 계산해 노출한다.
struct AssetRow: Identifiable, Sendable {
    let id: String
    let asset: Asset
    let symbol: String
    let exchange: Exchange
    let balance: Double
    let averageBuyPrice: Double
    let currentPrice: Double  // ticker 없으면 0
    let currentValue: Double  // balance * currentPrice
    let profit: Double        // currentValue - balance * averageBuyPrice (cost basis 없으면 0)
    let profitRate: Double    // 수익률 % (cost basis 없으면 0)
    let hasCostBasis: Bool
    let hasTicker: Bool
    let quoteCurrency: QuoteCurrency
}

// Asset이 Hashable이 아니므로 Hashable 자동 synthesis는 불가.
// SwiftUI Table은 Identifiable만 요구하므로 Hashable이 필요 없다.
