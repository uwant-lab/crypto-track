// CryptoTrack/Views/Dashboard/DashboardToolbar.swift
import SwiftUI

/// 대시보드 상단의 컨트롤 바: dust 토글, 마지막 갱신 시각, 새로고침 버튼,
/// 그리고 (해당되는 경우) 해외 거래소 평단가 동기화 버튼.
struct DashboardToolbar: View {
    @Binding var hideDust: Bool
    let lastRefresh: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    /// 해외 거래소 평단가 동기화가 필요한 상태 (= `averageBuyPrice == 0`인
    /// 보유 자산이 있는 경우). false면 버튼 자체를 숨긴다.
    let needsCostBasisSync: Bool
    /// 현재 동기화 중인지 — 버튼 disable + 스피너 표시용.
    let isCostBasisSyncing: Bool
    let onCostBasisSync: () -> Void

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

            if needsCostBasisSync {
                Button(action: onCostBasisSync) {
                    HStack(spacing: 4) {
                        if isCostBasisSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "function")
                        }
                        Text("해외 평단가 동기화")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isCostBasisSyncing)
            }

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
        onRefresh: {},
        needsCostBasisSync: true,
        isCostBasisSyncing: false,
        onCostBasisSync: {}
    )
    .padding()
}
