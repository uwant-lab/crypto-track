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
    /// 사용자가 평균 매수가를 직접 수정했는지 여부 (업비트·빗썸 API `avg_buy_price_modified`)
    var avgBuyPriceModified: Bool = false
    /// 자산이 속한 거래소
    let exchange: Exchange
    /// 마지막 동기화 시각
    let lastUpdated: Date

    /// 총 매수 금액
    var totalCost: Double {
        balance * averageBuyPrice
    }
}

extension Asset {
    /// 평단가가 0 초과면 cost basis 제공으로 간주. 해외 거래소처럼 API가 평단가를
    /// 안 주는 경우 0이 들어오므로 false가 된다.
    var hasCostBasis: Bool { averageBuyPrice > 0 }

    /// 이 자산이 속한 통화 (거래소에서 도출).
    var quoteCurrency: QuoteCurrency { exchange.quoteCurrency }
}
