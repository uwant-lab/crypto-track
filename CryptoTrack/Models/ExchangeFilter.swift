import Foundation

/// 대시보드 거래소 필터 탭 선택 상태.
enum ExchangeFilter: Hashable, Sendable {
    case all
    case exchange(Exchange)
}
