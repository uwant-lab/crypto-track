import SwiftUI

/// 타임프레임 선택 버튼 목록을 수평으로 표시하는 컴포넌트입니다.
struct TimeframePickerView: View {
    let selectedTimeframe: ChartTimeframe
    let onSelect: (ChartTimeframe) async -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChartTimeframe.allCases, id: \.self) { timeframe in
                    TimeframeChip(
                        timeframe: timeframe,
                        isSelected: timeframe == selectedTimeframe,
                        onTap: { Task { await onSelect(timeframe) } }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Chip

private struct TimeframeChip: View {
    let timeframe: ChartTimeframe
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(timeframe.rawValue)
                .font(.system(size: 13, weight: isSelected ? .bold : .regular, design: .monospaced))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    TimeframePickerView(selectedTimeframe: .hour1) { _ in }
        .padding()
}
