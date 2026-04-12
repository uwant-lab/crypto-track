import SwiftUI

/// 가격 변동값에 색상을 매핑하는 헬퍼.
enum PriceColor {
    static func color(for value: Double, mode: PriceColorMode) -> Color {
        guard value != 0 else { return .secondary }
        switch mode {
        case .korean:
            return value > 0 ? .red : .blue
        case .global:
            return value > 0 ? .green : .red
        }
    }
}
