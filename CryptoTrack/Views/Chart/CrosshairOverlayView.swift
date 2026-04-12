import SwiftUI

/// 롱프레스 시 표시되는 크로스헤어 오버레이 컴포넌트입니다.
struct CrosshairOverlayView: View {
    /// 크로스헤어 위치 (차트 영역 내 좌표)
    let position: CGPoint
    /// 선택된 캔들 데이터
    let kline: Kline
    /// 차트 영역 크기
    let chartSize: CGSize

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }

    var body: some View {
        ZStack {
            crosshairLines
            infoCard
        }
    }

    // MARK: - Crosshair Lines

    private var crosshairLines: some View {
        Canvas { context, size in
            // 수직선
            var vPath = Path()
            vPath.move(to: CGPoint(x: position.x, y: 0))
            vPath.addLine(to: CGPoint(x: position.x, y: size.height))
            context.stroke(
                vPath,
                with: .color(.primary.opacity(0.6)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )

            // 수평선
            var hPath = Path()
            hPath.move(to: CGPoint(x: 0, y: position.y))
            hPath.addLine(to: CGPoint(x: size.width, y: position.y))
            context.stroke(
                hPath,
                with: .color(.primary.opacity(0.6)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Info Card

    private var infoCard: some View {
        let cardWidth: CGFloat = 160
        let cardHeight: CGFloat = 120
        let padding: CGFloat = 8

        // 카드 위치: 크로스헤어 오른쪽 상단, 화면 밖으로 나가면 반대쪽으로
        var x = position.x + padding
        if x + cardWidth > chartSize.width {
            x = position.x - cardWidth - padding
        }
        var y = position.y - cardHeight - padding
        if y < 0 {
            y = position.y + padding
        }

        return OHLCVCard(kline: kline, dateFormatter: dateFormatter)
            .frame(width: cardWidth)
            .position(x: x + cardWidth / 2, y: y + cardHeight / 2)
            .allowsHitTesting(false)
    }
}

// MARK: - OHLCV Card

private struct OHLCVCard: View {
    let kline: Kline
    let dateFormatter: DateFormatter

    private var candleColor: Color { kline.isBullish ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(dateFormatter.string(from: kline.timestamp))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Divider()

            Group {
                ohlcRow("O", value: kline.open)
                ohlcRow("H", value: kline.high)
                ohlcRow("L", value: kline.low)
                ohlcRow("C", value: kline.close, highlight: true)
            }

            Divider()

            HStack {
                Text("V")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatVolume(kline.volume))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(candleColor.opacity(0.4), lineWidth: 1)
        )
    }

    private func ohlcRow(_ label: String, value: Double, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(highlight ? candleColor : .secondary)
            Spacer()
            Text(formatPrice(value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(highlight ? candleColor : .primary)
        }
    }

    private func formatPrice(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else if value >= 1 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.6f", value)
        }
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - Preview

#Preview {
    let kline = ChartViewModel.generateSampleKlines(
        symbol: "BTC", exchange: .binance, timeframe: .hour1, count: 1
    )[0]
    return ZStack {
        Color.gray.opacity(0.1)
        CrosshairOverlayView(
            position: CGPoint(x: 200, y: 150),
            kline: kline,
            chartSize: CGSize(width: 390, height: 300)
        )
    }
    .frame(width: 390, height: 300)
}
