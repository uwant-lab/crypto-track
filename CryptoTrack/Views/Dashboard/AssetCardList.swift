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
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(row.symbol)
                            .font(.headline)
                        if showBadges {
                            ExchangeBadgeRow(exchanges: row.exchanges, size: 16)
                        }
                    }
                    Text("\(PriceFormatter.formatBalance(row.totalBalance)) \(row.symbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PriceFormatter.formatPrice(row.currentValue, currency: row.quoteCurrency))
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
            Divider()
            HStack(spacing: 16) {
                infoPair(
                    label: "평단",
                    value: row.hasCostBasis
                        ? PriceFormatter.formatPrice(row.averageBuyPrice, currency: row.quoteCurrency)
                        : "—"
                )
                infoPair(
                    label: "현재가",
                    value: row.hasTicker
                        ? PriceFormatter.formatPrice(row.currentPrice, currency: row.quoteCurrency)
                        : "—"
                )
                if row.hasPartialCostBasis {
                    Text("일부 미제공")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background.secondary)
        )
    }

    private func infoPair(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}
#endif
