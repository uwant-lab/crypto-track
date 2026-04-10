import SwiftUI

/// 거래소 API 키 관리 설정 화면입니다.
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var lockManager = AppLockManager.shared

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

                SecuritySectionView(lockManager: lockManager)
            }
            .navigationTitle("설정")
            .onAppear {
                viewModel.refreshSavedExchanges()
            }
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
                    .scaleEffect(0.8)
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

// MARK: - Security Section

private struct SecuritySectionView: View {
    var lockManager: AppLockManager

    private let authService = BiometricAuthService.shared

    var body: some View {
        Section {
            if authService.canUseBiometrics() {
                Toggle(isOn: Binding(
                    get: { lockManager.isAppLockEnabled },
                    set: { _ in lockManager.toggleAppLock() }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: biometricIcon)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("앱 잠금 (\(authService.biometricType.rawValue))")
                                .font(.body)
                            Text("앱 시작 시 생체 인증으로 잠금 해제")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "lock.slash")
                        .foregroundStyle(.secondary)
                    Text("이 기기에서는 생체 인증을 사용할 수 없습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("보안")
        } footer: {
            if authService.canUseBiometrics() {
                Text("앱이 백그라운드로 이동하면 자동으로 잠깁니다.")
            }
        }
    }

    private var biometricIcon: String {
        switch authService.biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .none:
            return "lock.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
