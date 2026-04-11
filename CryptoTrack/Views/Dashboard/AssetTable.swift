// CryptoTrack/Views/Dashboard/AssetTable.swift
#if os(macOS)
import SwiftUI

/// macOS-only section-aware table renderer.
///
/// SwiftUI `Table` does not support sections natively, so we stack two
/// `Table`s vertically when showing both KRW and USD groups. Each section
/// owns its own `KeyPathComparator` binding so column-click sorting is
/// independent per section. When only one section is present (i.e. the
/// `.exchange` filter is selected), we render a single `Table`.
struct AssetTableSections: View {
    let sections: [RowSection]
    @Binding var krwSortOrder: [KeyPathComparator<PortfolioRow>]
    @Binding var usdSortOrder: [KeyPathComparator<PortfolioRow>]
    let showHeaders: Bool
    let colorMode: PriceColorMode
    let sparkline: (PortfolioRow) -> [Double]?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if showHeaders {
                        Text(section.id.sectionTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    sectionTable(for: section)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionTable(for section: RowSection) -> some View {
        switch section.id {
        case .krw:
            table(rows: section.rows, sortOrder: $krwSortOrder)
        case .usdt:
            table(rows: section.rows, sortOrder: $usdSortOrder)
        }
    }

    private func table(
        rows: [PortfolioRow],
        sortOrder: Binding<[KeyPathComparator<PortfolioRow>]>
    ) -> some View {
        Table(rows, sortOrder: sortOrder) {
            TableColumn("코인") { row in
                HStack(spacing: 8) {
                    Text(row.symbol).font(.body.weight(.semibold))
                    if showHeaders {
                        ExchangeBadgeRow(exchanges: row.exchanges, size: 14)
                    }
                }
            }
            .width(min: 110, ideal: 160)

            TableColumn("보유량", value: \.totalBalance) { row in
                Text(PriceFormatter.formatBalance(row.totalBalance))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 120)

            TableColumn("평단가", value: \.averageBuyPrice) { row in
                if row.hasCostBasis {
                    HStack(spacing: 4) {
                        Text(PriceFormatter.formatPrice(row.averageBuyPrice, currency: row.quoteCurrency))
                            .monospacedDigit()
                        if row.hasPartialCostBasis {
                            Text("일부")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 140)

            TableColumn("매수금액", value: \.totalCost) { row in
                if row.hasCostBasis {
                    Text(PriceFormatter.formatAmount(row.totalCost, currency: row.quoteCurrency))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 150)

            TableColumn("현재가", value: \.currentPrice) { row in
                if row.hasTicker {
                    Text(PriceFormatter.formatPrice(row.currentPrice, currency: row.quoteCurrency))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 140)

            TableColumn("24h") { row in
                if let rate = row.changeRate24h {
                    Text(PriceFormatter.formatRate(rate))
                        .foregroundStyle(PriceColor.color(for: rate, mode: colorMode))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 70, ideal: 90)

            TableColumn("7일") { row in
                Sparkline(
                    prices: sparkline(row) ?? [],
                    colorMode: colorMode
                )
                .frame(width: 60, height: 20)
            }
            .width(min: 70, ideal: 80)

            TableColumn("평가금액", value: \.currentValue) { row in
                Text(PriceFormatter.formatAmount(row.currentValue, currency: row.quoteCurrency))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .width(min: 110, ideal: 150)

            TableColumn("수익", value: \.profit) { row in
                if row.hasCostBasis {
                    Text(PriceFormatter.formatSignedAmount(row.profit, currency: row.quoteCurrency))
                        .foregroundStyle(PriceColor.color(for: row.profit, mode: colorMode))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 150)

            TableColumn("수익률", value: \.profitRate) { row in
                if row.hasCostBasis {
                    Text(PriceFormatter.formatRate(row.profitRate))
                        .foregroundStyle(PriceColor.color(for: row.profitRate, mode: colorMode))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)
        }
    }
}
#endif
