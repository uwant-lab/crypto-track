import SwiftUI

/// Canvas that renders sub-panel indicators (RSI, MACD, Stochastic, OBV) below volume bars.
/// Syncs horizontally with the candlestick chart via the same `klines` (visible range).
struct IndicatorSubPanelCanvas: View {
    let klines: [Kline]
    let config: IndicatorConfig
    let values: [IndicatorValue]

    private let yAxisWidth: CGFloat = 60
    private let labelFontSize: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            let chartRect = CGRect(
                x: 0,
                y: 4,
                width: geo.size.width - yAxisWidth,
                height: geo.size.height - 8
            )
            let candleWidth = klines.isEmpty ? 0 : chartRect.width / CGFloat(klines.count)

            Canvas { context, size in
                switch config.type {
                case .rsi:
                    drawRSI(context: context, size: size, chartRect: chartRect, candleWidth: candleWidth)
                case .macd:
                    drawMACD(context: context, size: size, chartRect: chartRect, candleWidth: candleWidth)
                case .stochastic:
                    drawStochastic(context: context, size: size, chartRect: chartRect, candleWidth: candleWidth)
                case .obv:
                    drawOBV(context: context, size: size, chartRect: chartRect, candleWidth: candleWidth)
                default:
                    break
                }
            }
        }
    }

    // MARK: - RSI

    private func drawRSI(
        context: GraphicsContext,
        size: CGSize,
        chartRect: CGRect,
        candleWidth: CGFloat
    ) {
        let yRange = 0.0...100.0
        drawHorizontalGuide(context: context, chartRect: chartRect, yRange: yRange, value: 70, label: "70", color: .red.opacity(0.5))
        drawHorizontalGuide(context: context, chartRect: chartRect, yRange: yRange, value: 30, label: "30", color: .green.opacity(0.5))
        drawHorizontalGuide(context: context, chartRect: chartRect, yRange: yRange, value: 50, label: "50", color: .secondary.opacity(0.3))
        drawSingleLine(context: context, chartRect: chartRect, candleWidth: candleWidth, valueKey: "rsi", yRange: yRange, color: config.color)
        drawYAxisLabel(context: context, size: size, chartRect: chartRect, label: "RSI")
    }

    // MARK: - MACD

    private func drawMACD(
        context: GraphicsContext,
        size: CGSize,
        chartRect: CGRect,
        candleWidth: CGFloat
    ) {
        guard candleWidth > 0, !values.isEmpty else { return }
        let indexMap = timestampIndexMap()

        // Compute Y range from all macd/signal/histogram values
        var allVals: [Double] = []
        for iv in values {
            if let m = iv.values["macd"]     { allVals.append(m) }
            if let s = iv.values["signal"]   { allVals.append(s) }
            if let h = iv.values["histogram"]{ allVals.append(h) }
        }
        guard let minVal = allVals.min(), let maxVal = allVals.max() else { return }
        let padding = (maxVal - minVal) * 0.1
        let yRange = (minVal - padding)...(maxVal + padding)

        // Zero line
        drawHorizontalGuide(context: context, chartRect: chartRect, yRange: yRange, value: 0, label: "0", color: .secondary.opacity(0.4))

        // Histogram bars
        let candleSpacingRatio: CGFloat = 0.2
        let barWidth = max(1, candleWidth - candleWidth * candleSpacingRatio * 2)
        for iv in values {
            guard let hist = iv.values["histogram"],
                  let idx  = indexMap[iv.timestamp] else { continue }
            let x = chartRect.minX + (CGFloat(idx) + 0.5) * candleWidth
            let zeroY = yPos(for: 0, in: chartRect, range: yRange)
            let valY  = yPos(for: hist, in: chartRect, range: yRange)
            let barRect = CGRect(
                x: x - barWidth / 2,
                y: min(zeroY, valY),
                width: barWidth,
                height: abs(zeroY - valY)
            )
            let barColor: Color = hist >= 0 ? .green.opacity(0.6) : .red.opacity(0.6)
            context.fill(Path(barRect), with: .color(barColor))
        }

        // MACD line
        drawSingleLine(context: context, chartRect: chartRect, candleWidth: candleWidth, valueKey: "macd", yRange: yRange, color: config.color)
        // Signal line
        drawSingleLine(context: context, chartRect: chartRect, candleWidth: candleWidth, valueKey: "signal", yRange: yRange, color: .orange)

        drawYAxisLabel(context: context, size: size, chartRect: chartRect, label: "MACD")
    }

    // MARK: - Stochastic

    private func drawStochastic(
        context: GraphicsContext,
        size: CGSize,
        chartRect: CGRect,
        candleWidth: CGFloat
    ) {
        let yRange = 0.0...100.0
        drawHorizontalGuide(context: context, chartRect: chartRect, yRange: yRange, value: 80, label: "80", color: .red.opacity(0.5))
        drawHorizontalGuide(context: context, chartRect: chartRect, yRange: yRange, value: 20, label: "20", color: .green.opacity(0.5))
        drawSingleLine(context: context, chartRect: chartRect, candleWidth: candleWidth, valueKey: "k", yRange: yRange, color: config.color)
        drawSingleLine(context: context, chartRect: chartRect, candleWidth: candleWidth, valueKey: "d", yRange: yRange, color: .orange)
        drawYAxisLabel(context: context, size: size, chartRect: chartRect, label: "Stoch")
    }

    // MARK: - OBV

    private func drawOBV(
        context: GraphicsContext,
        size: CGSize,
        chartRect: CGRect,
        candleWidth: CGFloat
    ) {
        guard !values.isEmpty else { return }
        let allVals = values.compactMap { $0.values["obv"] }
        guard let minVal = allVals.min(), let maxVal = allVals.max() else { return }
        let padding = max(abs(maxVal - minVal) * 0.05, 1.0)
        let yRange = (minVal - padding)...(maxVal + padding)

        drawSingleLine(context: context, chartRect: chartRect, candleWidth: candleWidth, valueKey: "obv", yRange: yRange, color: config.color)
        drawYAxisLabel(context: context, size: size, chartRect: chartRect, label: "OBV")
    }

    // MARK: - Shared drawing primitives

    private func drawSingleLine(
        context: GraphicsContext,
        chartRect: CGRect,
        candleWidth: CGFloat,
        valueKey: String,
        yRange: ClosedRange<Double>,
        color: Color
    ) {
        guard candleWidth > 0, !values.isEmpty else { return }
        let indexMap = timestampIndexMap()
        var path = Path()
        var started = false

        for iv in values {
            guard let val = iv.values[valueKey],
                  let idx = indexMap[iv.timestamp] else { continue }
            let x = chartRect.minX + (CGFloat(idx) + 0.5) * candleWidth
            let y = yPos(for: val, in: chartRect, range: yRange)
            if !started {
                path.move(to: CGPoint(x: x, y: y))
                started = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    private func drawHorizontalGuide(
        context: GraphicsContext,
        chartRect: CGRect,
        yRange: ClosedRange<Double>,
        value: Double,
        label: String,
        color: Color
    ) {
        let y = yPos(for: value, in: chartRect, range: yRange)
        var path = Path()
        path.move(to: CGPoint(x: chartRect.minX, y: y))
        path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

        let text = Text(label)
            .font(.system(size: labelFontSize, design: .monospaced))
            .foregroundStyle(color)
        context.draw(text, at: CGPoint(x: chartRect.maxX + 4, y: y), anchor: .leading)
    }

    private func drawYAxisLabel(
        context: GraphicsContext,
        size: CGSize,
        chartRect: CGRect,
        label: String
    ) {
        let text = Text(label)
            .font(.system(size: labelFontSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.secondary)
        context.draw(text, at: CGPoint(x: chartRect.maxX + 4, y: chartRect.minY), anchor: .topLeading)
    }

    // MARK: - Helpers

    private func yPos(for value: Double, in rect: CGRect, range: ClosedRange<Double>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return rect.midY }
        let fraction = (range.upperBound - value) / span
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
    let config = IndicatorConfig(type: .rsi, parameters: ["period": 14])
    let values = IndicatorCalculator.calculateRSI(klines: vm.visibleKlines, period: 14)
    IndicatorSubPanelCanvas(
        klines: vm.visibleKlines,
        config: config,
        values: values
    )
    .frame(height: 80)
    .padding()
    .background(AppColor.background)
}
