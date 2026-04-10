import SwiftUI

/// 포트폴리오 전체 요약을 표시하는 카드 뷰입니다.
struct PortfolioSummaryView: View {
    let totalValue: Double
    let totalProfit: Double
    let totalProfitRate: Double

    private var isProfitable: Bool { totalProfit >= 0 }
    private var profitColor: Color { isProfitable ? .green : .red }
    private var directionSymbol: String { isProfitable ? "arrow.up.right" : "arrow.down.right" }

    var body: some View {
        VStack(spacing: 12) {
            Text("총 평가액")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(totalValue.formatted(.currency(code: "KRW").precision(.fractionLength(0))))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            HStack(spacing: 6) {
                Image(systemName: directionSymbol)
                    .font(.caption.bold())

                Text(totalProfit.formatted(.currency(code: "KRW").precision(.fractionLength(0))))
                    .font(.subheadline.bold())

                Text(String(format: "(%.2f%%)", totalProfitRate))
                    .font(.subheadline)
            }
            .foregroundStyle(profitColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(profitColor.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview("수익") {
    PortfolioSummaryView(
        totalValue: 45_620_000,
        totalProfit: 3_120_000,
        totalProfitRate: 7.34
    )
    .padding()
}

#Preview("손실") {
    PortfolioSummaryView(
        totalValue: 38_500_000,
        totalProfit: -1_500_000,
        totalProfitRate: -3.75
    )
    .padding()
}
