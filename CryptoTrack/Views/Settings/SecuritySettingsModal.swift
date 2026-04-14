import SwiftUI

struct SecuritySettingsModal: View {
    @State private var lockManager = AppLockManager.shared
    @State private var navigationPath = NavigationPath()
    @Environment(\.dismiss) private var dismiss

    private let authService = BiometricAuthService.shared

    var body: some View {
        NavigationStack(path: $navigationPath) {
            settingsContent
                .navigationTitle("보안 설정")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("완료") { dismiss() }
                    }
                }
                .navigationDestination(for: PINFlowMode.self) { mode in
                    PINInputView(mode: mode) {
                        navigationPath = NavigationPath()
                        lockManager.refreshPINState()
                        if mode == .remove {
                            lockManager.isBiometricEnabled = false
                        }
                    }
                }
        }
        .frame(idealWidth: 420, idealHeight: 500)
    }

    // MARK: - Content

    private var settingsContent: some View {
        List {
            appLockSection
            convenienceSection
            if lockManager.isPINSet {
                dangerZoneSection
            }
            Section {} footer: {
                Text("앱이 백그라운드로 전환되면 자동으로 잠깁니다.")
            }
        }
    }

    // MARK: - App Lock Section

    private var appLockSection: some View {
        Section {
            if lockManager.isPINSet {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PIN 잠금")
                            .font(.body)
                        Text("활성화됨")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }

                Button {
                    navigationPath.append(PINFlowMode.change)
                } label: {
                    HStack {
                        Text("PIN 변경")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    navigationPath.append(PINFlowMode.setup)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.badge.plus")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PIN 잠금 설정")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("4자리 PIN으로 앱을 보호합니다")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("설정")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("앱 잠금")
        }
    }

    // MARK: - Convenience Section

    private var convenienceSection: some View {
        Section {
            if lockManager.isPINSet && authService.canUseBiometrics() {
                Toggle(isOn: Binding(
                    get: { lockManager.isBiometricEnabled },
                    set: { lockManager.isBiometricEnabled = $0 }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: biometricIcon)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(authService.biometricType.rawValue)로 잠금 해제")
                                .font(.body)
                            Text("PIN 대신 생체인증으로 빠르게 해제")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if lockManager.isPINSet {
                HStack(spacing: 12) {
                    Image(systemName: "lock.slash")
                        .foregroundStyle(.secondary)
                    Text("이 기기에서는 생체 인증을 사용할 수 없습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: biometricIcon)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("생체 인증으로 잠금 해제")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text("PIN 설정 후 사용할 수 있습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(0.5)
            }
        } header: {
            Text("편의 기능")
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        Section {
            Button {
                navigationPath.append(PINFlowMode.remove)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PIN 해제")
                            .font(.body)
                            .foregroundStyle(.red)
                        Text("현재 PIN 입력 후 잠금을 해제합니다")
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
            Text("위험 영역")
        }
    }

    // MARK: - Helpers

    private var biometricIcon: String {
        switch authService.biometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .none: "lock.fill"
        }
    }
}

#Preview {
    SecuritySettingsModal()
}
