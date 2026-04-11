import SwiftUI

/// Tiny 7-day close-price line chart used in dashboard rows.
///
/// - Given 2+ points, draws a polyline across the full width, normalized to
///   the min/max of the supplied prices so the slope is readable at small sizes.
/// - Given 0 or 1 points, renders a dashed baseline placeholder.
///
/// The stroke color is derived from the price direction: rising → up color,
/// falling → down color, flat → secondary. The price-color mapping comes from
/// `PriceColor.color(for:mode:)` so the sparkline matches the 수익률 coloring
/// convention (Korean vs Western mode).
struct Sparkline: View {
    let prices: [Double]
    var colorMode: PriceColorMode = .korean
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            if prices.count >= 2 {
                Canvas { context, size in
                    let path = buildPath(in: size)
                    context.stroke(
                        path,
                        with: .color(strokeColor),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                }
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(
                    Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Path

    private func buildPath(in size: CGSize) -> Path {
        guard prices.count >= 2 else { return Path() }
        let minValue = prices.min() ?? 0
        let maxValue = prices.max() ?? 1
        let range = max(maxValue - minValue, .ulpOfOne)
        let stepX = size.width / CGFloat(prices.count - 1)

        var path = Path()
        for (i, price) in prices.enumerated() {
            let x = CGFloat(i) * stepX
            let normalized = (price - minValue) / range
            // Invert y: top of the view = maximum price.
            let y = size.height * (1 - CGFloat(normalized))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    // MARK: - Color

    private var strokeColor: Color {
        guard let first = prices.first, let last = prices.last else {
            return .secondary
        }
        // Use same polarity logic as profit display: delta positive → "up" color.
        return PriceColor.color(for: last - first, mode: colorMode)
    }
}

#Preview("sparkline states") {
    VStack(alignment: .leading, spacing: 16) {
        HStack {
            Text("상승").frame(width: 60, alignment: .leading)
            Sparkline(prices: [100, 102, 99, 104, 108, 110, 115])
                .frame(width: 80, height: 24)
        }
        HStack {
            Text("하락").frame(width: 60, alignment: .leading)
            Sparkline(prices: [115, 112, 110, 108, 104, 102, 99])
                .frame(width: 80, height: 24)
        }
        HStack {
            Text("횡보").frame(width: 60, alignment: .leading)
            Sparkline(prices: [100, 101, 100, 102, 100, 101, 100])
                .frame(width: 80, height: 24)
        }
        HStack {
            Text("no data").frame(width: 60, alignment: .leading)
            Sparkline(prices: [])
                .frame(width: 80, height: 24)
        }
    }
    .padding()
}
