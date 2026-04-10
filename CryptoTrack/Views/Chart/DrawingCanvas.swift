import SwiftUI

/// 저장된 드로잉을 캔들스틱 차트 위에 렌더링하는 캔버스 오버레이입니다.
struct DrawingCanvas: View {
    let viewModel: DrawingViewModel
    let klines: [Kline]
    let chartRect: CGRect
    let priceRange: ClosedRange<Double>

    // Fibonacci levels
    private let fibRetracementLevels: [(Double, String)] = [
        (0.0, "0%"),
        (0.236, "23.6%"),
        (0.382, "38.2%"),
        (0.5, "50%"),
        (0.618, "61.8%"),
        (0.786, "78.6%"),
        (1.0, "100%")
    ]

    private let fibExtensionLevels: [(Double, String)] = [
        (1.0, "100%"),
        (1.272, "127.2%"),
        (1.618, "161.8%"),
        (2.0, "200%"),
        (2.618, "261.8%")
    ]

    var body: some View {
        Canvas { context, size in
            // Draw completed visible drawings
            for drawing in viewModel.visibleDrawings {
                drawDrawing(drawing, context: &context, isSelected: drawing.id == viewModel.selectedDrawingId)
            }
            // Draw in-progress drawing
            if let inProgress = viewModel.inProgressDrawing {
                drawDrawing(inProgress, context: &context, isSelected: false, isInProgress: true)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Dispatch

    private func drawDrawing(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        isSelected: Bool,
        isInProgress: Bool = false
    ) {
        let color = drawing.color.color
        let lineWidth = drawing.lineWidth

        switch drawing.type {
        case .trendLine:
            drawTrendLine(drawing, context: &context, color: color, lineWidth: lineWidth, isSelected: isSelected)
        case .horizontalLine:
            drawHorizontalLine(drawing, context: &context, color: color, lineWidth: lineWidth, isSelected: isSelected)
        case .verticalLine:
            drawVerticalLine(drawing, context: &context, color: color, lineWidth: lineWidth, isSelected: isSelected)
        case .ray:
            drawRay(drawing, context: &context, color: color, lineWidth: lineWidth, isSelected: isSelected)
        case .fibonacciRetracement:
            drawFibonacci(drawing, context: &context, color: color, levels: fibRetracementLevels, isSelected: isSelected)
        case .fibonacciExtension:
            drawFibonacci(drawing, context: &context, color: color, levels: fibExtensionLevels, isSelected: isSelected)
        case .rectangle:
            drawRectangle(drawing, context: &context, color: color, lineWidth: lineWidth, isSelected: isSelected)
        case .parallelChannel:
            drawParallelChannel(drawing, context: &context, color: color, lineWidth: lineWidth, isSelected: isSelected)
        case .textLabel:
            drawTextLabel(drawing, context: &context, color: color, isSelected: isSelected)
        case .priceLabel:
            drawPriceLabel(drawing, context: &context, color: color, lineWidth: lineWidth, isSelected: isSelected)
        }

        if isSelected {
            drawHandles(drawing, context: &context)
        }
    }

    // MARK: - Trend Line

    private func drawTrendLine(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        color: Color,
        lineWidth: Double,
        isSelected: Bool
    ) {
        guard drawing.points.count >= 2 else {
            drawPartialPoints(drawing, context: &context, color: color)
            return
        }
        let p1 = canvasPoint(for: drawing.points[0])
        let p2 = canvasPoint(for: drawing.points[1])
        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    // MARK: - Horizontal Line

    private func drawHorizontalLine(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        color: Color,
        lineWidth: Double,
        isSelected: Bool
    ) {
        guard let point = drawing.points.first else { return }
        let y = yPosition(for: point.price)
        var path = Path()
        path.move(to: CGPoint(x: chartRect.minX, y: y))
        path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)

        // Price label
        let label = Text(formatPrice(point.price))
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(color)
        context.draw(label, at: CGPoint(x: chartRect.maxX + 4, y: y), anchor: .leading)
    }

    // MARK: - Vertical Line

    private func drawVerticalLine(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        color: Color,
        lineWidth: Double,
        isSelected: Bool
    ) {
        guard let point = drawing.points.first else { return }
        let x = xPosition(for: point.timestamp)
        guard x >= chartRect.minX && x <= chartRect.maxX else { return }
        var path = Path()
        path.move(to: CGPoint(x: x, y: chartRect.minY))
        path.addLine(to: CGPoint(x: x, y: chartRect.maxY))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    // MARK: - Ray

    private func drawRay(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        color: Color,
        lineWidth: Double,
        isSelected: Bool
    ) {
        guard drawing.points.count >= 2 else {
            drawPartialPoints(drawing, context: &context, color: color)
            return
        }
        let p1 = canvasPoint(for: drawing.points[0])
        let p2 = canvasPoint(for: drawing.points[1])

        // Extend ray from p1 through p2 to chart boundary
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        guard dx != 0 || dy != 0 else { return }

        let end = extendToChartBounds(from: p1, direction: CGPoint(x: dx, y: dy))
        var path = Path()
        path.move(to: p1)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    // MARK: - Fibonacci

    private func drawFibonacci(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        color: Color,
        levels: [(Double, String)],
        isSelected: Bool
    ) {
        guard drawing.points.count >= 2 else {
            drawPartialPoints(drawing, context: &context, color: color)
            return
        }
        let highPrice = max(drawing.points[0].price, drawing.points[1].price)
        let lowPrice = min(drawing.points[0].price, drawing.points[1].price)
        let span = highPrice - lowPrice

        for (level, label) in levels {
            let price = highPrice - span * level
            let y = yPosition(for: price)
            guard y >= chartRect.minY && y <= chartRect.maxY else { continue }

            var path = Path()
            path.move(to: CGPoint(x: chartRect.minX, y: y))
            path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 0.8)

            let labelText = Text("\(label) \(formatPrice(price))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(color.opacity(0.9))
            context.draw(labelText, at: CGPoint(x: chartRect.minX + 4, y: y - 2), anchor: .bottomLeading)
        }
    }

    // MARK: - Rectangle

    private func drawRectangle(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        color: Color,
        lineWidth: Double,
        isSelected: Bool
    ) {
        guard drawing.points.count >= 2 else {
            drawPartialPoints(drawing, context: &context, color: color)
            return
        }
        let p1 = canvasPoint(for: drawing.points[0])
        let p2 = canvasPoint(for: drawing.points[1])
        let rect = CGRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )
        context.fill(Path(rect), with: .color(color.opacity(0.1)))
        context.stroke(Path(rect), with: .color(color), lineWidth: lineWidth)
    }

    // MARK: - Parallel Channel

    private func drawParallelChannel(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        color: Color,
        lineWidth: Double,
        isSelected: Bool
    ) {
        guard drawing.points.count >= 2 else {
            drawPartialPoints(drawing, context: &context, color: color)
            return
        }
        let p1 = canvasPoint(for: drawing.points[0])
        let p2 = canvasPoint(for: drawing.points[1])

        var path1 = Path()
        path1.move(to: p1)
        path1.addLine(to: p2)
        context.stroke(path1, with: .color(color), lineWidth: lineWidth)

        if drawing.points.count >= 3 {
            let p3 = canvasPoint(for: drawing.points[2])
            let offset = CGPoint(x: p3.x - p1.x, y: p3.y - p1.y)
            let p4 = CGPoint(x: p2.x + offset.x, y: p2.y + offset.y)

            var path2 = Path()
            path2.move(to: p3)
            path2.addLine(to: p4)
            context.stroke(path2, with: .color(color), lineWidth: lineWidth)

            // Fill between channels
            var fillPath = Path()
            fillPath.move(to: p1)
            fillPath.addLine(to: p2)
            fillPath.addLine(to: p4)
            fillPath.addLine(to: p3)
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(color.opacity(0.08)))
        }
    }

    // MARK: - Text Label

    private func drawTextLabel(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        color: Color,
        isSelected: Bool
    ) {
        guard let point = drawing.points.first else { return }
        let pos = canvasPoint(for: point)
        let displayText = drawing.text ?? "텍스트"
        let label = Text(displayText)
            .font(.system(size: 12))
            .foregroundStyle(color)
        context.draw(label, at: pos, anchor: .bottomLeading)
    }

    // MARK: - Price Label

    private func drawPriceLabel(
        _ drawing: ChartDrawing,
        context: inout GraphicsContext,
        color: Color,
        lineWidth: Double,
        isSelected: Bool
    ) {
        guard let point = drawing.points.first else { return }
        let y = yPosition(for: point.price)
        let x = xPosition(for: point.timestamp).clamped(to: chartRect.minX...chartRect.maxX)

        // Short horizontal tick
        var tickPath = Path()
        tickPath.move(to: CGPoint(x: x - 10, y: y))
        tickPath.addLine(to: CGPoint(x: x + 10, y: y))
        context.stroke(tickPath, with: .color(color), lineWidth: lineWidth)

        let label = Text(formatPrice(point.price))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(color)
        context.draw(label, at: CGPoint(x: x + 12, y: y), anchor: .leading)
    }

    // MARK: - Handles (selected drawing)

    private func drawHandles(_ drawing: ChartDrawing, context: inout GraphicsContext) {
        for point in drawing.points {
            let pos = canvasPoint(for: point)
            let handleSize: CGFloat = 8
            let handleRect = CGRect(
                x: pos.x - handleSize / 2,
                y: pos.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(Path(ellipseIn: handleRect), with: .color(.white))
            context.stroke(Path(ellipseIn: handleRect), with: .color(drawing.color.color), lineWidth: 1.5)
        }
    }

    // MARK: - Partial / In-progress

    private func drawPartialPoints(_ drawing: ChartDrawing, context: inout GraphicsContext, color: Color) {
        for point in drawing.points {
            let pos = canvasPoint(for: point)
            let r: CGFloat = 4
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.6)))
        }
    }

    // MARK: - Coordinate Helpers

    private func yPosition(for price: Double) -> CGFloat {
        let span = priceRange.upperBound - priceRange.lowerBound
        guard span > 0 else { return chartRect.midY }
        let fraction = (priceRange.upperBound - price) / span
        return chartRect.minY + CGFloat(fraction) * chartRect.height
    }

    private func xPosition(for timestamp: Date) -> CGFloat {
        guard klines.count > 1 else { return chartRect.midX }
        let first = klines.first!.timestamp.timeIntervalSinceReferenceDate
        let last = klines.last!.timestamp.timeIntervalSinceReferenceDate
        let span = last - first
        guard span > 0 else { return chartRect.midX }
        let fraction = (timestamp.timeIntervalSinceReferenceDate - first) / span
        return chartRect.minX + CGFloat(fraction) * chartRect.width
    }

    private func canvasPoint(for drawingPoint: DrawingPoint) -> CGPoint {
        CGPoint(
            x: xPosition(for: drawingPoint.timestamp),
            y: yPosition(for: drawingPoint.price)
        )
    }

    private func extendToChartBounds(from origin: CGPoint, direction: CGPoint) -> CGPoint {
        var t = CGFloat.infinity
        if direction.x > 0 {
            t = min(t, (chartRect.maxX - origin.x) / direction.x)
        } else if direction.x < 0 {
            t = min(t, (chartRect.minX - origin.x) / direction.x)
        }
        if direction.y > 0 {
            t = min(t, (chartRect.maxY - origin.y) / direction.y)
        } else if direction.y < 0 {
            t = min(t, (chartRect.minY - origin.y) / direction.y)
        }
        if t == .infinity { t = 0 }
        return CGPoint(x: origin.x + direction.x * t, y: origin.y + direction.y * t)
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
}

// MARK: - CGFloat clamped helper

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
