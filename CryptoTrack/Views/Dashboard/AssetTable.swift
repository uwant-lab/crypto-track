// CryptoTrack/Views/Dashboard/AssetTable.swift
#if os(macOS)
import SwiftUI

/// macOS 전용: SwiftUI Table로 자산 목록을 컴팩트하게 표시.
/// 컬럼 헤더 클릭 시 정렬은 SwiftUI Table이 자동 처리한다 (KeyPathComparator 바인딩).
struct AssetTable: View {
    let rows: [AssetRow]
    @Binding var sortOrder: [KeyPathComparator<AssetRow>]
    let colorMode: PriceColorMode

    var body: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("코인") { row in
                HStack(spacing: 8) {
                    Text(row.symbol)
                        .font(.body.weight(.semibold))
                    Text(row.exchange.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.15))
                        )
                }
            }
            .width(min: 120, ideal: 140)

            TableColumn("보유량", value: \.balance) { row in
                Text(PriceFormatter.formatBalance(row.balance))
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn("평단가", value: \.averageBuyPrice) { row in
                if row.hasCostBasis {
                    Text(PriceFormatter.formatPrice(row.averageBuyPrice, currency: row.quoteCurrency))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("현재가", value: \.currentPrice) { row in
                if row.hasTicker {
                    Text(PriceFormatter.formatPrice(row.currentPrice, currency: row.quoteCurrency))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("평가금액", value: \.currentValue) { row in
                Text(PriceFormatter.formatPrice(row.currentValue, currency: row.quoteCurrency))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .width(min: 110, ideal: 140)

            TableColumn("수익률", value: \.profitRate) { row in
                if row.hasCostBasis {
                    HStack(spacing: 4) {
                        Text(PriceFormatter.formatRate(row.profitRate))
                            .foregroundStyle(PriceColor.color(for: row.profitRate, mode: colorMode))
                            .monospacedDigit()
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)
        }
    }
}

#Preview {
    @Previewable @State var sortOrder: [KeyPathComparator<AssetRow>] = [
        KeyPathComparator(\AssetRow.currentValue, order: .reverse)
    ]
    let sample = DashboardViewModel.preview.displayedRows
    return AssetTable(rows: sample, sortOrder: $sortOrder, colorMode: .korean)
        .frame(minWidth: 800, minHeight: 400)
}
#endif
