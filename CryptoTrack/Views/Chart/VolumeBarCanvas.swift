import SwiftUI

/// SwiftUI Canvas 기반 거래량 바 차트 렌더러입니다.
/// CandlestickCanvas와 동일한 수평 배치(줌/스크롤)로 동기화됩니다.
struct VolumeBarCanvas: View {
    let klines: [Kline]

    private let yAxisWidth: CGFloat = 60
    private let candleSpacingRatio: CGFloat = 0.2

    var body: some View {
        GeometryReader { geo in
            let chartRect = CGRect(
                x: 0,
                y: 0,
                width: geo.size.width - yAxisWidth,
                height: geo.size.height
            )
            let maxVolume = klines.map(\.volume).max() ?? 1

            Canvas { context, size in
                drawVolumeBars(
                    context: context,
                    chartRect: chartRect,
                    maxVolume: maxVolume
                )
                drawVolumeLabel(context: context, size: size, maxVolume: maxVolume)
            }
        }
    }

    // MARK: - Drawing

    private func drawVolumeBars(
        context: GraphicsContext,
        chartRect: CGRect,
        maxVolume: Double
    ) {
        guard !klines.isEmpty else { return }
        let candleWidth = chartRect.width / CGFloat(klines.count)
        let spacing = candleWidth * candleSpacingRatio
        let barWidth = max(1, candleWidth - spacing * 2)

        for (index, kline) in klines.enumerated() {
            let centerX = chartRect.minX + (CGFloat(index) + 0.5) * candleWidth
            let barHeight = CGFloat(kline.volume / maxVolume) * chartRect.height
            let barRect = CGRect(
                x: centerX - barWidth / 2,
                y: chartRect.maxY - barHeight,
                width: barWidth,
                height: barHeight
            )
            let barColor: Color = kline.isBullish ? .green.opacity(0.6) : .red.opacity(0.6)
            context.fill(Path(barRect), with: .color(barColor))
        }
    }

    private func drawVolumeLabel(
        context: GraphicsContext,
        size: CGSize,
        maxVolume: Double
    ) {
        let label = formatVolume(maxVolume)
        let text = Text(label)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color.secondary)
        context.draw(text, at: CGPoint(x: size.width - yAxisWidth + 4, y: 2), anchor: .topLeading)
    }

    // MARK: - Helpers

    private func formatVolume(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
}

// MARK: - Preview

#Preview {
    let vm = ChartViewModel.preview
    VolumeBarCanvas(klines: vm.visibleKlines)
        .frame(height: 80)
        .padding()
}
