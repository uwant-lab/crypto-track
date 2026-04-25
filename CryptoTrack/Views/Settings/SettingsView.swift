import SwiftUI

/// 거래소 API 키 관리 설정 화면입니다.
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var lockManager = AppLockManager.shared
    @State private var syncService = CloudSyncService.shared
    @State private var showSecurityModal = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.allExchanges, id: \.self) { exchange in
                        NavigationLink {
                            ExchangeSetupView(
                                exchange: exchange,
                                settingsViewModel: viewModel
                            )
                        } label: {
                            ExchangeRowView(
                                exchange: exchange,
                                isSaved: viewModel.savedExchanges.contains(exchange),
                                status: viewModel.connectionStatus[exchange] ?? .untested
                            )
                        }
                    }
                } header: {
                    Text("거래소 API 키")
                } footer: {
                    Text("API 키는 기기의 Keychain에 안전하게 저장됩니다.")
                }

                DisplaySettingsSectionView()

                SecuritySettingsTriggerView(
                    lockManager: lockManager,
                    showModal: $showSecurityModal
                )

                iCloudSyncSectionView(syncService: syncService)
            }
            .navigationTitle("설정")
            .onAppear {
                viewModel.refreshSavedExchanges()
            }
            .task {
                await viewModel.refreshConnectionStatuses()
            }
        }
        .sheet(isPresented: $showSecurityModal) {
            SecuritySettingsModal()
        }
    }
}

// MARK: - Exchange Row

private struct ExchangeRowView: View {
    let exchange: Exchange
    let isSaved: Bool
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exchange.rawValue)
                    .font(.body)
                if isSaved {
                    Text(status.displayText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                } else {
                    Text("미설정")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusIndicator
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isSaved {
            switch status {
            case .untested:
                Image(systemName: "key.fill")
                    .foregroundStyle(.orange)
            case .testing:
                ProgressView()
                    .controlSize(.small)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        } else {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch status {
        case .untested:
            return .secondary
        case .testing:
            return .secondary
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
}

// MARK: - Security Section (Modal Trigger)

private struct SecuritySettingsTriggerView: View {
    let lockManager: AppLockManager
    @Binding var showModal: Bool

    var body: some View {
        Section {
            Button {
                showModal = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("보안")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text(lockManager.isPINSet ? "PIN 잠금 활성화됨" : "잠금 미설정")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("보안")
        } footer: {
            if lockManager.isPINSet {
                Text("앱이 백그라운드로 이동하면 자동으로 잠깁니다.")
            }
        }
    }
}

// MARK: - iCloud Sync Section

private struct iCloudSyncSectionView: View {
    var syncService: CloudSyncService
    @State private var isSyncing = false

    private var connectionText: String {
        syncService.isICloudAvailable ? "연결됨" : "연결 안됨"
    }

    private var connectionColor: Color {
        syncService.isICloudAvailable ? .green : .secondary
    }

    private var lastSyncText: String {
        guard let date = syncService.lastSyncDate else { return "없음" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Section {
            HStack {
                Image(systemName: "icloud")
                    .foregroundStyle(connectionColor)
                Text("iCloud 상태")
                Spacer()
                Text(connectionText)
                    .foregroundStyle(connectionColor)
                    .font(.subheadline)
            }

            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("마지막 동기화")
                Spacer()
                Text(lastSyncText)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Button {
                guard syncService.isICloudAvailable else { return }
                isSyncing = true
                syncService.synchronizeNow()
                ExchangeManager.shared.syncFromCloud()
                AppLockManager.shared.syncFromCloud()
                isSyncing = false
            } label: {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath.icloud")
                    }
                    Text("지금 동기화")
                }
            }
            .disabled(!syncService.isICloudAvailable || isSyncing)

        } header: {
            Text("iCloud 동기화")
        } footer: {
            if !syncService.isICloudAvailable {
                Text("iCloud에 로그인하면 기기 간 설정이 자동으로 동기화됩니다.")
            } else {
                Text("거래소 등록 정보와 앱 설정이 iCloud를 통해 동기화됩니다. API 키는 보안 정책상 동기화되지 않습니다.")
            }
        }
    }
}

// MARK: - Display Section

private struct DisplaySettingsSectionView: View {
    @State private var settings = AppSettingsManager.shared

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { settings.priceColorMode },
                set: { settings.priceColorMode = $0 }
            )) {
                ForEach(PriceColorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(.purple)
                    Text("가격 변동 색상")
                }
            }
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.menu)
            #endif
        } header: {
            Text("표시")
        } footer: {
            Text("한국 표준은 상승=빨강, 하락=파랑입니다. 글로벌 표준은 상승=초록, 하락=빨강입니다.")
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
