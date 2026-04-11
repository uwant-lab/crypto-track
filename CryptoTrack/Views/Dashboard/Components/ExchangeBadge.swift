import SwiftUI

#if canImport(UIKit)
import UIKit
private func loadPlatformImage(named name: String) -> UIImage? { UIImage(named: name) }
#elseif canImport(AppKit)
import AppKit
private func loadPlatformImage(named name: String) -> NSImage? { NSImage(named: name) }
#endif

/// Circular badge identifying a single exchange.
///
/// Rendering strategy:
/// 1. If the bundled image asset named `exchange.logoAssetName` exists,
///    display the image clipped to a circle.
/// 2. Otherwise fall back to a brand-colored circle with the exchange's
///    monogram in white.
///
/// This hybrid is the kill-switch contract: deleting a logo asset
/// automatically reverts to the monogram without any code changes.
struct ExchangeBadge: View {
    let exchange: Exchange
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            if loadPlatformImage(named: exchange.logoAssetName) != nil {
                Image(exchange.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(exchange.brandColor)
                    .frame(width: size, height: size)
                Text(exchange.monogram)
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(exchange.rawValue))
    }
}

/// Horizontal strip of `ExchangeBadge`s, ordered by `Exchange.allCases`
/// for stable rendering. When more than `maxVisible` exchanges are
/// present, the remainder is collapsed to a `+N` indicator.
struct ExchangeBadgeRow: View {
    let exchanges: [Exchange]
    var size: CGFloat = 16
    var maxVisible: Int = 4

    var body: some View {
        let sorted = Exchange.allCases.filter { exchanges.contains($0) }
        let visible = sorted.prefix(maxVisible)
        let overflow = max(sorted.count - maxVisible, 0)

        HStack(spacing: -4) {
            ForEach(Array(visible), id: \.self) { exchange in
                ExchangeBadge(exchange: exchange, size: size)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5)
                    )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
        }
    }
}

#Preview("ExchangeBadge — all exchanges") {
    HStack(spacing: 12) {
        ForEach(Exchange.allCases, id: \.self) { ex in
            ExchangeBadge(exchange: ex, size: 28)
        }
    }
    .padding()
}

#Preview("ExchangeBadgeRow — overflow") {
    VStack(alignment: .leading, spacing: 12) {
        ExchangeBadgeRow(exchanges: [.upbit, .bithumb], size: 16)
        ExchangeBadgeRow(exchanges: [.upbit, .bithumb, .coinone, .korbit], size: 16)
        ExchangeBadgeRow(exchanges: [.upbit, .bithumb, .coinone, .korbit, .binance, .okx], size: 16)
    }
    .padding()
}
