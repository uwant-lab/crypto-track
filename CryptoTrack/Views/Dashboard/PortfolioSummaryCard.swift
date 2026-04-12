// CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift
import SwiftUI

/// KRW와 USD 그룹을 두 블록으로 분리해 표시하는 요약 카드.
/// 한쪽 통화 자산이 없으면 그쪽은 그리지 않는다.
struct PortfolioSummaryCard: View {
    let krw: CurrencySummary?
    let usd: CurrencySummary?
    let colorMode: PriceColorMode
    var krwSlices: [AllocationSlice] = []
    var usdSlices: [AllocationSlice] = []

    @AppStorage("donutChartExpanded") private var isChartExpanded: Bool = true

    var body: some View {
        VStack(spacing: 12) {
            if let krw {
                SummaryBlock(
                    summary: krw, colorMode: colorMode,
                    slices: krwSlices, isChartExpanded: $isChartExpanded
                )
            }
            if krw != nil && usd != nil {
                Divider()
            }
            if let usd {
                SummaryBlock(
                    summary: usd, colorMode: colorMode,
                    slices: usdSlices, isChartExpanded: $isChartExpanded
                )
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
    let slices: [AllocationSlice]
    @Binding var isChartExpanded: Bool

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS: 가로 배치 (접기 없음)

    private var macOSLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            summaryContent
            if !slices.isEmpty {
                Divider()
                    .frame(height: 120)
                DonutChartView(slices: slices, chartSize: 100)
            }
        }
    }

    // MARK: - iOS: 세로 배치 + 접기/펼치기

    private var iOSLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryContent

            if !slices.isEmpty {
                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isChartExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("보유 비중")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isChartExpanded ? 0 : -90))
                    }
                }
                .buttonStyle(.plain)

                if isChartExpanded {
                    DonutChartView(slices: slices)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - 요약 정보 (공통)

    private var summaryContent: some View {
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
        colorMode: .korean,
        krwSlices: [
            AllocationSlice(symbol: "BTC", percentage: 60.0, value: 7_708_380),
            AllocationSlice(symbol: "ETH", percentage: 25.0, value: 3_211_825),
            AllocationSlice(symbol: "XRP", percentage: 15.0, value: 1_927_095),
        ],
        usdSlices: [
            AllocationSlice(symbol: "SOL", percentage: 55.0, value: 1_786),
            AllocationSlice(symbol: "AVAX", percentage: 45.0, value: 1_461),
        ]
    )
    .padding()
}
