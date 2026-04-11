// CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift
import SwiftUI

/// KRW와 USD 그룹을 두 블록으로 분리해 표시하는 요약 카드.
/// 한쪽 통화 자산이 없으면 그쪽은 그리지 않는다.
struct PortfolioSummaryCard: View {
    let krw: CurrencySummary?
    let usd: CurrencySummary?
    let colorMode: PriceColorMode

    var body: some View {
        VStack(spacing: 12) {
            if let krw {
                SummaryBlock(summary: krw, colorMode: colorMode)
            }
            if krw != nil && usd != nil {
                Divider()
            }
            if let usd {
                SummaryBlock(summary: usd, colorMode: colorMode)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.secondary)
        )
    }
}

private struct SummaryBlock: View {
    let summary: CurrencySummary
    let colorMode: PriceColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.currency.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(PriceFormatter.formatRate(summary.profitRate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PriceColor.color(for: summary.profitRate, mode: colorMode))
                    .monospacedDigit()
            }

            valueRow(label: "총 매수", value: PriceFormatter.formatAmount(summary.totalCost, currency: summary.currency))
            valueRow(label: "총 평가", value: PriceFormatter.formatAmount(summary.totalValue, currency: summary.currency), emphasized: true)
            valueRow(
                label: "수익",
                value: PriceFormatter.formatSignedAmount(summary.totalProfit, currency: summary.currency),
                tint: PriceColor.color(for: summary.totalProfit, mode: colorMode)
            )

            if summary.hasUnknownCostBasis {
                Text("일부 자산 평단가 미제공")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func valueRow(label: String, value: String, emphasized: Bool = false, tint: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasized ? .title3.weight(.bold) : .subheadline.weight(.medium))
                .foregroundStyle(tint ?? .primary)
                .monospacedDigit()
        }
    }
}

#Preview {
    PortfolioSummaryCard(
        krw: CurrencySummary(
            currency: .krw,
            totalValue: 12_847_300,
            totalCost: 11_600_000,
            totalProfit: 1_247_300,
            profitRate: 10.74,
            hasUnknownCostBasis: false
        ),
        usd: CurrencySummary(
            currency: .usdt,
            totalValue: 3_247.50,
            totalCost: 0,
            totalProfit: 0,
            profitRate: 0,
            hasUnknownCostBasis: true
        ),
        colorMode: .korean
    )
    .padding()
}
