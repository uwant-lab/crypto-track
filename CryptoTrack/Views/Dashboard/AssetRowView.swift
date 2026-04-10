import SwiftUI

/// 자산 목록에서 개별 자산 항목을 표시하는 행 컴포넌트입니다.
struct AssetRowView: View {
    let asset: Asset
    let currentValue: Double
    let profit: Double
    let profitRate: Double

    private var isProfitable: Bool { profit >= 0 }
    private var profitColor: Color { isProfitable ? .green : .red }
    private var profitSign: String { isProfitable ? "+" : "" }

    var body: some View {
        HStack(spacing: 12) {
            symbolBadge
            assetInfo
            Spacer()
            valueInfo
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    private var symbolBadge: some View {
        ZStack {
            Circle()
                .fill(badgeColor(for: asset.exchange).opacity(0.15))
                .frame(width: 44, height: 44)
            Text(asset.symbol.prefix(3))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(badgeColor(for: asset.exchange))
        }
    }

    private var assetInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.symbol)
                .font(.headline)
            HStack(spacing: 4) {
                Text(asset.exchange.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.6g", asset.balance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var valueInfo: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(currentValue.formatted(.number.precision(.fractionLength(0))))
                .font(.subheadline.bold())

            HStack(spacing: 3) {
                Text("\(profitSign)\(String(format: "%.2f", profitRate))%")
                    .font(.caption.bold())
                    .foregroundStyle(profitColor)

                Image(systemName: isProfitable ? "triangle.fill" : "triangle.fill")
                    .font(.system(size: 7))
                    .rotationEffect(isProfitable ? .zero : .degrees(180))
                    .foregroundStyle(profitColor)
            }
        }
    }

    // MARK: - Helpers

    private func badgeColor(for exchange: Exchange) -> Color {
        switch exchange {
        case .upbit:    return .blue
        case .binance:  return .yellow
        case .bithumb:  return .orange
        case .bybit:    return .purple
        case .coinone:  return .green
        case .korbit:   return .red
        case .okx:      return .teal
        }
    }
}

// MARK: - Preview

#Preview {
    let vm = DashboardViewModel.preview
    List(vm.assets) { asset in
        AssetRowView(
            asset: asset,
            currentValue: vm.currentValue(for: asset),
            profit: vm.profit(for: asset),
            profitRate: vm.profitRate(for: asset)
        )
    }
}
