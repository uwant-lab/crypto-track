// CryptoTrack/Views/Dashboard/AssetCardList.swift
#if !os(macOS)
import SwiftUI

/// iOS 전용: 카드형 행으로 자산 목록을 표시.
struct AssetCardList: View {
    let rows: [AssetRow]
    let colorMode: PriceColorMode

    var body: some View {
        List(rows) { row in
            AssetCardRow(row: row, colorMode: colorMode)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .listStyle(.plain)
    }
}

private struct AssetCardRow: View {
    let row: AssetRow
    let colorMode: PriceColorMode

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.symbol)
                        .font(.headline)
                    Text("\(row.exchange.rawValue) · \(PriceFormatter.formatBalance(row.balance)) \(row.symbol)")
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

#Preview {
    let sample = DashboardViewModel.preview.displayedRows
    return AssetCardList(rows: sample, colorMode: .korean)
}
#endif
