// CryptoTrack/Views/Dashboard/AssetCardList.swift
#if !os(macOS)
import SwiftUI

/// iOS-only section-aware card list. Renders one `Section` per
/// quoteCurrency with a header when `showSectionHeaders == true`
/// (i.e. the "전체" filter). When a specific exchange is selected we
/// pass `showSectionHeaders: false` so the list renders without header
/// decoration.
struct AssetCardList: View {
    let sections: [RowSection]
    let showSectionHeaders: Bool
    let colorMode: PriceColorMode

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        AssetCardRow(
                            row: row,
                            showBadges: showSectionHeaders,
                            colorMode: colorMode
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    if showSectionHeaders {
                        Text(section.id.sectionTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct AssetCardRow: View {
    let row: PortfolioRow
    let showBadges: Bool
    let colorMode: PriceColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            metricsGrid
            if row.hasPartialCostBasis {
                Text("일부 자산 평단가 미제공")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background.secondary)
        )
    }

    // MARK: - Header (symbol + badges / value + profit rate)

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.symbol)
                        .font(.headline)
                    if showBadges {
                        ExchangeBadgeRow(exchanges: row.exchanges, size: 16)
                    }
                }
                HStack(spacing: 6) {
                    Text(PriceFormatter.formatBalance(row.totalBalance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let rate = row.changeRate24h {
                        Text(PriceFormatter.formatRate(rate))
                            .font(.caption)
                            .foregroundStyle(PriceColor.color(for: rate, mode: colorMode))
                            .monospacedDigit()
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(PriceFormatter.formatAmount(row.currentValue, currency: row.quoteCurrency))
                    .font(.headline)
                    .monospacedDigit()
                if row.hasCostBasis {
                    Text(PriceFormatter.formatRate(row.profitRate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PriceColor.color(for: row.profitRate, mode: colorMode))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Metric grid (평단 / 현재가 / 매수금액 / 수익)

    private var metricsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                metric(
                    label: "평단",
                    value: row.hasCostBasis
                        ? PriceFormatter.formatPrice(row.averageBuyPrice, currency: row.quoteCurrency)
                        : "—"
                )
                metric(
                    label: "현재가",
                    value: row.hasTicker
                        ? PriceFormatter.formatPrice(row.currentPrice, currency: row.quoteCurrency)
                        : "—"
                )
            }
            GridRow {
                metric(
                    label: "매수금액",
                    value: row.hasCostBasis
                        ? PriceFormatter.formatAmount(row.totalCost, currency: row.quoteCurrency)
                        : "—"
                )
                metric(
                    label: "수익",
                    value: row.hasCostBasis
                        ? PriceFormatter.formatSignedAmount(row.profit, currency: row.quoteCurrency)
                        : "—",
                    tint: row.hasCostBasis
                        ? PriceColor.color(for: row.profit, mode: colorMode)
                        : nil
                )
            }
        }
    }

    private func metric(label: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint ?? .primary)
                .monospacedDigit()
        }
    }
}
#endif
