import SwiftUI

/// Canvas overlay that draws overlay indicators (MA, EMA, Bollinger Bands)
/// on top of the candlestick chart using the same coordinate system.
struct IndicatorOverlayCanvas: View {
    let klines: [Kline]
    let indicators: [IndicatorConfig]
    let indicatorValues: [String: [IndicatorValue]]

    private let yAxisWidth: CGFloat = 60
    private let xAxisHeight: CGFloat = 24

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

            Canvas { context, _ in
                for config in indicators where config.isVisible && config.position == .overlay {
                    guard let values = indicatorValues[config.id] else { continue }
                    switch config.type {
                    case .bollingerBands:
                        drawBollingerBands(
                            context: context,
                            values: values,
                            config: config,
                            chartRect: chartRect,
                            priceRange: priceRange,
                            candleWidth: candleWidth
                        )
                    default:
                        drawLine(
                            context: context,
                            values: values,
                            valueKey: config.type == .ema ? "ema" : "ma",
                            config: config,
                            chartRect: chartRect,
                            priceRange: priceRange,
                            candleWidth: candleWidth
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Drawing helpers

    private func drawLine(
        context: GraphicsContext,
        values: [IndicatorValue],
        valueKey: String,
        config: IndicatorConfig,
        chartRect: CGRect,
        priceRange: ClosedRange<Double>,
        candleWidth: CGFloat
    ) {
        guard candleWidth > 0, !values.isEmpty else { return }

        // Build a timestamp → index map for the visible klines
        let indexMap = timestampIndexMap()
        var path = Path()
        var started = false

        for iv in values {
            guard let price = iv.values[valueKey],
                  let idx = indexMap[iv.timestamp] else { continue }
            let x = chartRect.minX + (CGFloat(idx) + 0.5) * candleWidth
            let y = yPosition(for: price, in: chartRect, range: priceRange)
            if !started {
                path.move(to: CGPoint(x: x, y: y))
                started = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.stroke(path, with: .color(config.color), lineWidth: 1.5)
    }

    private func drawBollingerBands(
        context: GraphicsContext,
        values: [IndicatorValue],
        config: IndicatorConfig,
        chartRect: CGRect,
        priceRange: ClosedRange<Double>,
        candleWidth: CGFloat
    ) {
        guard candleWidth > 0, !values.isEmpty else { return }
        let indexMap = timestampIndexMap()

        var upperPoints: [CGPoint] = []
        var middlePoints: [CGPoint] = []
        var lowerPoints: [CGPoint] = []

        for iv in values {
            guard let upper  = iv.values["upper"],
                  let middle = iv.values["middle"],
                  let lower  = iv.values["lower"],
                  let idx    = indexMap[iv.timestamp] else { continue }
            let x = chartRect.minX + (CGFloat(idx) + 0.5) * candleWidth
            upperPoints.append(CGPoint(x: x, y: yPosition(for: upper,  in: chartRect, range: priceRange)))
            middlePoints.append(CGPoint(x: x, y: yPosition(for: middle, in: chartRect, range: priceRange)))
            lowerPoints.append(CGPoint(x: x, y: yPosition(for: lower,  in: chartRect, range: priceRange)))
        }

        guard !upperPoints.isEmpty else { return }

        // Fill between upper and lower bands
        var fillPath = Path()
        fillPath.move(to: upperPoints[0])
        for pt in upperPoints.dropFirst() { fillPath.addLine(to: pt) }
        for pt in lowerPoints.reversed()  { fillPath.addLine(to: pt) }
        fillPath.closeSubpath()
        context.fill(fillPath, with: .color(config.color.opacity(0.08)))

        // Draw the three lines
        for (points, alpha) in [(upperPoints, 0.8), (middlePoints, 1.0), (lowerPoints, 0.8)] {
            var linePath = Path()
            if let first = points.first {
                linePath.move(to: first)
                for pt in points.dropFirst() { linePath.addLine(to: pt) }
            }
            context.stroke(linePath, with: .color(config.color.opacity(alpha)), lineWidth: 1.2)
        }
    }

    // MARK: - Coordinate helpers

    private func computePriceRange() -> ClosedRange<Double> {
        guard !klines.isEmpty else { return 0...1 }
        let low  = klines.map(\.low).min()!
        let high = klines.map(\.high).max()!
        let padding = (high - low) * 0.05
        return (low - padding)...(high + padding)
    }

    private func yPosition(for price: Double, in rect: CGRect, range: ClosedRange<Double>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return rect.midY }
        let fraction = (range.upperBound - price) / span
        return rect.minY + CGFloat(fraction) * rect.height
    }

    private func timestampIndexMap() -> [Date: Int] {
        var map = [Date: Int]()
        map.reserveCapacity(klines.count)
        for (i, k) in klines.enumerated() {
            map[k.timestamp] = i
        }
        return map
    }
}

// MARK: - Preview

#Preview {
    let vm = ChartViewModel.preview
    let config = IndicatorConfig(type: .ma, parameters: ["period": 20])
    let values = IndicatorCalculator.calculateMA(klines: vm.visibleKlines, period: 20)
    IndicatorOverlayCanvas(
        klines: vm.visibleKlines,
        indicators: [config],
        indicatorValues: [config.id: values]
    )
    .frame(height: 300)
    .padding()
}
