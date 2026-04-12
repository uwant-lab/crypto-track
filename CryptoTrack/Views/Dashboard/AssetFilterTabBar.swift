// CryptoTrack/Views/Dashboard/AssetFilterTabBar.swift
import SwiftUI

/// 대시보드 상단의 거래소 필터 탭 바.
/// "전체" + 등록된 거래소들만 동적으로 표시한다.
struct AssetFilterTabBar: View {
    @Binding var selected: ExchangeFilter
    let available: [Exchange]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "전체",
                    isSelected: selected == .all
                ) {
                    selected = .all
                }
                ForEach(available, id: \.self) { exchange in
                    FilterChip(
                        label: exchange.rawValue,
                        isSelected: selected == .exchange(exchange)
                    ) {
                        selected = .exchange(exchange)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var filter: ExchangeFilter = .all
    return AssetFilterTabBar(
        selected: $filter,
        available: [.upbit, .bithumb, .binance]
    )
    .padding()
}
