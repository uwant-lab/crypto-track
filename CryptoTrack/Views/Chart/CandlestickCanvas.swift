import SwiftUI

/// SwiftUI Canvas 기반 캔들스틱 차트 렌더러입니다.
struct CandlestickCanvas: View {
    let klines: [Kline]
    let onZoom: (CGFloat) -> Void
    let onScroll: (CGFloat, CGFloat) -> Void
    let onCrosshairChanged: (CGPoint?, Kline?) -> Void

    // MARK: - Layout Constants

    private let yAxisWidth: CGFloat = 60
    private let xAxisHeight: CGFloat = 24
    private let candleSpacingRatio: CGFloat = 0.2   // 캔들 너비 대비 간격 비율
    private let gridLineCount: Int = 5

    // MARK: - Gesture State

    @State private var lastMagnification: CGFloat = 1.0
    @State private var lastDragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let chartRect = CGRect(
                x: 0,
                y: 0,
                width: geo.size.width - yAxisWidth,
                height: geo.size.height - xAxisHeight
            )
            let priceRange = computePriceRange()
            let candleWidth = klines.isEmpty ? 0 : chartRect.width / CGFloat(klines.count)

            ZStack(alignment: .topLeading) {
                // 메인 캔버스
                Canvas { context, size in
                    drawGrid(context: context, size: size, chartRect: chartRect, priceRange: priceRange)
                    drawCandles(context: context, chartRect: chartRect, priceRange: priceRange, candleWidth: candleWidth)
                    drawYAxis(context: context, size: size, chartRect: chartRect, priceRange: priceRange)
                    drawXAxis(context: context, size: size, chartRect: chartRect, candleWidth: candleWidth)
                }

                // 제스처 영역 (y축 제외)
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: chartRect.width, height: geo.size.height)
                    .gesture(magnifyGesture())
                    .gesture(dragGesture(candleWidth: candleWidth))
                    .gesture(longPressAndDragGesture(chartRect: chartRect, priceRange: priceRange, candleWidth: candleWidth))
            }
        }
    }

    // MARK: - Price Range

    private func computePriceRange() -> ClosedRange<Double> {
        guard !klines.isEmpty else { return 0...1 }
        let low = klines.map(\.low).min()!
        let high = klines.map(\.high).max()!
        let padding = (high - low) * 0.05
        return (low - padding)...(high + padding)
    }

    // MARK: - Drawing

    private func drawGrid(
        context: GraphicsContext,
        size: CGSize,
        chartRect: CGRect,
        priceRange: ClosedRange<Double>
    ) {
        let gridColor = Color.secondary.opacity(0.15)

        // 수평 그리드 (가격 레벨)
        for i in 0...gridLineCount {
            let y = chartRect.minY + chartRect.height * CGFloat(i) / CGFloat(gridLineCount)
            var path = Path()
            path.move(to: CGPoint(x: chartRect.minX, y: y))
            path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawCandles(
        context: GraphicsContext,
        chartRect: CGRect,
        priceRange: ClosedRange<Double>,
        candleWidth: CGFloat
    ) {
        guard !klines.isEmpty else { return }
        let spacing = candleWidth * candleSpacingRatio
        let bodyWidth = max(1, candleWidth - spacing * 2)

        for (index, kline) in klines.enumerated() {
            let centerX = chartRect.minX + (CGFloat(index) + 0.5) * candleWidth
            let bodyColor: Color = kline.isBullish ? .green : .red

            // 위크 (고저선)
            let highY = yPosition(for: kline.high, in: chartRect, range: priceRange)
            let lowY = yPosition(for: kline.low, in: chartRect, range: priceRange)
            var wickPath = Path()
            wickPath.move(to: CGPoint(x: centerX, y: highY))
            wickPath.addLine(to: CGPoint(x: centerX, y: lowY))
            context.stroke(wickPath, with: .color(bodyColor.opacity(0.8)), lineWidth: max(0.5, candleWidth * 0.08))

            // 캔들 바디 (시가-종가)
            let openY = yPosition(for: kline.open, in: chartRect, range: priceRange)
            let closeY = yPosition(for: kline.close, in: chartRect, range: priceRange)
            let bodyTop = min(openY, closeY)
            let bodyHeight = max(1, abs(openY - closeY))

            let bodyRect = CGRect(
                x: centerX - bodyWidth / 2,
                y: bodyTop,
                width: bodyWidth,
                height: bodyHeight
            )
            context.fill(Path(bodyRect), with: .color(bodyColor))
        }
    }

    private func drawYAxis(
        context: GraphicsContext,
        size: CGSize,
        chartRect: CGRect,
        priceRange: ClosedRange<Double>
    ) {
        let priceSpan = priceRange.upperBound - priceRange.lowerBound
        let xStart = chartRect.maxX + 4

        for i in 0...gridLineCount {
            let fraction = CGFloat(i) / CGFloat(gridLineCount)
            let y = chartRect.minY + chartRect.height * fraction
            let price = priceRange.upperBound - Double(fraction) * priceSpan

            let label = formatPrice(price)
            let text = Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.secondary)
            context.draw(text, at: CGPoint(x: xStart, y: y), anchor: .leading)
        }
    }

    private func drawXAxis(
        context: GraphicsContext,
        size: CGSize,
        chartRect: CGRect,
        candleWidth: CGFloat
    ) {
        guard !klines.isEmpty, candleWidth > 0 else { return }
        let labelEvery = max(1, Int(40 / candleWidth))  // 최소 40pt 간격
        let y = chartRect.maxY + 4
        let formatter = xLabelFormatter()

        for (index, kline) in klines.enumerated() {
            guard index % labelEvery == 0 else { continue }
            let x = chartRect.minX + (CGFloat(index) + 0.5) * candleWidth
            let label = formatter.string(from: kline.timestamp)
            let text = Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.secondary)
            context.draw(text, at: CGPoint(x: x, y: y), anchor: .top)
        }
    }

    // MARK: - Helpers

    private func yPosition(for price: Double, in rect: CGRect, range: ClosedRange<Double>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return rect.midY }
        let fraction = (range.upperBound - price) / span
        return rect.minY + CGFloat(fraction) * rect.height
    }

    private func formatPrice(_ price: Double) -> String {
        if price >= 10_000 {
            return String(format: "%.0f", price)
        } else if price >= 1 {
            return String(format: "%.2f", price)
        } else {
            return String(format: "%.4f", price)
        }
    }

    private func xLabelFormatter() -> DateFormatter {
        let f = DateFormatter()
        if klines.count > 1 {
            let span = klines.last!.timestamp.timeIntervalSince(klines.first!.timestamp)
            if span < 3600 * 24 {
                f.dateFormat = "HH:mm"
            } else if span < 3600 * 24 * 60 {
                f.dateFormat = "yyyy/MM/dd"
            } else {
                f.dateFormat = "yyyy/MM"
            }
        } else {
            f.dateFormat = "yyyy/MM/dd"
        }
        return f
    }

    private func klineIndex(at x: CGFloat, candleWidth: CGFloat) -> Int? {
        guard candleWidth > 0, !klines.isEmpty else { return nil }
        let index = Int(x / candleWidth)
        guard index >= 0 && index < klines.count else { return nil }
        return index
    }

    // MARK: - Gestures

    private func magnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastMagnification
                lastMagnification = value.magnification
                onZoom(delta)
            }
            .onEnded { _ in
                lastMagnification = 1.0
            }
    }

    private func dragGesture(candleWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                let delta = value.translation.width - lastDragOffset
                lastDragOffset = value.translation.width
                onScroll(delta, candleWidth)
            }
            .onEnded { _ in
                lastDragOffset = 0
            }
    }

    private func longPressAndDragGesture(
        chartRect: CGRect,
        priceRange: ClosedRange<Double>,
        candleWidth: CGFloat
    ) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if let drag = drag {
                        let pos = drag.location
                        let index = klineIndex(at: pos.x - chartRect.minX, candleWidth: candleWidth)
                        let kline = index.map { klines[$0] }
                        onCrosshairChanged(pos, kline)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                onCrosshairChanged(nil, nil)
            }
    }
}

// MARK: - Preview

#Preview {
    let vm = ChartViewModel.preview
    CandlestickCanvas(
        klines: vm.visibleKlines,
        onZoom: { _ in },
        onScroll: { _, _ in },
        onCrosshairChanged: { _, _ in }
    )
    .frame(height: 300)
    .padding()
}
