import Foundation

/// 가격 변동 색상 표시 모드.
enum PriceColorMode: String, Codable, Sendable, CaseIterable {
    /// 한국 표준: 상승=빨강, 하락=파랑
    case korean
    /// 글로벌 표준: 상승=초록, 하락=빨강
    case global

    var displayName: String {
        switch self {
        case .korean: return "한국 (빨/파)"
        case .global: return "글로벌 (초록/빨)"
        }
    }
}
