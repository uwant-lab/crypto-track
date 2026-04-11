// CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift
import SwiftUI

/// KRW와 USD 그룹을 두 줄로 분리해 표시하는 요약 카드.
/// 한쪽 통화 자산이 없으면 그쪽은 그리지 않는다.
struct PortfolioSummaryCard: View {
    let krw: CurrencySummary?
    let usd: CurrencySummary?
    let colorMode: PriceColorMode

    var body: some View {
        VStack(spacing: 12) {
            if let krw {
                SummaryRow(summary: krw, colorMode: colorMode)
            }
            if krw != nil && usd != nil {
                Divider()
            }
            if let usd {
                SummaryRow(summary: usd, colorMode: colorMode)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.secondary)
        )
    }
}

private struct SummaryRow: View {
    let summary: CurrencySummary
    let colorMode: PriceColorMode

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.currency.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(PriceFormatter.formatPrice(summary.totalValue, currency: summary.currency))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ProfitBadge(
                    rate: summary.profitRate,
                    profit: summary.totalProfit,
                    currency: summary.currency,
                    colorMode: colorMode
                )
                if summary.hasUnknownCostBasis {
                    Text("일부 자산 평단가 미제공")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
