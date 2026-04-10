import SwiftUI

enum AppColor {
    static var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    static var secondaryBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    static let bullish = Color.green
    static let bearish = Color.red
    static let profit = Color.green
    static let loss = Color.red

    // Exchange brand colors
    static func exchange(_ exchange: Exchange) -> Color {
        switch exchange {
        case .upbit: .blue
        case .binance: .yellow
        case .bithumb: .orange
        case .bybit: .purple
        case .coinone: .green
        case .korbit: .cyan
        case .okx: .indigo
        }
    }
}
