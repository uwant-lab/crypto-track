// CryptoTrack/Views/Dashboard/Components/DonutChartView.swift
import SwiftUI

/// 도넛 차트의 색상 팔레트.
private let donutColors: [Color] = [
    .green, .blue, .orange, .pink, .cyan,
    .purple, .yellow, .mint, .indigo, .teal,
    .brown, .red,
]

/// 도넛 차트 한 조각을 그리는 Shape.
private struct DonutSegment: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * 0.6

        var path = Path()
        path.addArc(
            center: center, radius: radius,
            startAngle: startAngle, endAngle: endAngle, clockwise: false
        )
        path.addArc(
            center: center, radius: innerRadius,
            startAngle: endAngle, endAngle: startAngle, clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

/// 도넛 차트 + 중앙 텍스트.
struct DonutChart: View {
    let slices: [AllocationSlice]
    let size: CGFloat

    var body: some View {
        ZStack {
            if slices.isEmpty {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: size * 0.2)
                    .frame(width: size, height: size)
            } else {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    DonutSegment(
                        startAngle: segment.start,
                        endAngle: segment.end
                    )
                    .fill(donutColors[index % donutColors.count])
                }
                .frame(width: size, height: size)
            }

            // 중앙 텍스트
            VStack(spacing: 2) {
                Text("비중")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(slices.count)종")
                    .font(.subheadline.weight(.bold))
            }
        }
        .frame(width: size, height: size)
    }

    /// 각 슬라이스의 시작/끝 각도를 계산한다.
    /// 12시 방향(-90°)부터 시계 방향으로 그린다.
    private var segments: [(start: Angle, end: Angle)] {
        var result: [(Angle, Angle)] = []
        // gap: 슬라이스 간 1° 간격
        let gapDegrees: Double = slices.count > 1 ? 1.0 : 0
        let totalGap = gapDegrees * Double(slices.count)
        let available = 360.0 - totalGap
        var current: Double = -90

        for slice in slices {
            let span = available * (slice.percentage / 100.0)
            let start = Angle.degrees(current)
            let end = Angle.degrees(current + span)
            result.append((start, end))
            current += span + gapDegrees
        }
        return result
    }
}

/// 범례 리스트.
struct DonutLegend: View {
    let slices: [AllocationSlice]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                HStack(spacing: 8) {
                    Circle()
                        .fill(donutColors[index % donutColors.count])
                        .frame(width: 8, height: 8)
                    Text(slice.symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(width: 40, alignment: .leading)
                    Spacer()
                    Text(String(format: "%.1f%%", slice.percentage))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
    }
}

/// 도넛 차트 + 범례를 가로로 배치하는 조합 뷰.
struct DonutChartView: View {
    let slices: [AllocationSlice]
    var chartSize: CGFloat = 120

    var body: some View {
        HStack(spacing: 16) {
            DonutChart(slices: slices, size: chartSize)
            DonutLegend(slices: slices)
        }
    }
}

// MARK: - Preview

#Preview("donut chart") {
    DonutChartView(
        slices: [
            AllocationSlice(symbol: "BTC", percentage: 36.2, value: 31_000_000),
            AllocationSlice(symbol: "ETH", percentage: 25.5, value: 9_920_000),
            AllocationSlice(symbol: "XRP", percentage: 18.3, value: 984_000),
            AllocationSlice(symbol: "SOL", percentage: 12.1, value: 2_475_000),
            AllocationSlice(symbol: "ADA", percentage: 7.9, value: 3_100_000),
        ]
    )
    .padding()
    .background(.background.secondary)
    .preferredColorScheme(.dark)
}

#Preview("single asset") {
    DonutChartView(
        slices: [
            AllocationSlice(symbol: "BTC", percentage: 100, value: 31_000_000),
        ]
    )
    .padding()
    .background(.background.secondary)
    .preferredColorScheme(.dark)
}

#Preview("empty") {
    DonutChartView(slices: [])
        .padding()
        .background(.background.secondary)
        .preferredColorScheme(.dark)
}
