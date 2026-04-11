// CryptoTrack/Views/Dashboard/DashboardToolbar.swift
import SwiftUI

/// 대시보드 상단의 컨트롤 바: dust 토글, 마지막 갱신 시각, 새로고침 버튼.
struct DashboardToolbar: View {
    @Binding var hideDust: Bool
    let lastRefresh: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $hideDust) {
                Text("소액 숨김")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            #if os(macOS)
            .controlSize(.mini)
            #endif

            Spacer()

            if let lastRefresh {
                Text("갱신: \(formatTime(lastRefresh))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    @Previewable @State var hide = true
    return DashboardToolbar(
        hideDust: $hide,
        lastRefresh: Date(),
        isRefreshing: false,
        onRefresh: {}
    )
    .padding()
}
