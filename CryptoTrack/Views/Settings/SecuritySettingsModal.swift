import SwiftUI

/// 보안 설정 전용 모달 — PIN 설정/변경/해제 및 생체인증 토글을 관리합니다.
struct SecuritySettingsModal: View {
    @State private var lockManager = AppLockManager.shared
    @State private var navigationPath = NavigationPath()
    @State private var canUseBiometrics: Bool = false
    @State private var biometricTypeRawValue: String = ""
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
                        lockManager.refreshPINState()
                        navigationPath = NavigationPath()
                    }
                }
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 460, idealHeight: 500)
        .task {
            canUseBiometrics = authService.canUseBiometrics()
            biometricTypeRawValue = authService.biometricType.rawValue
        }
    }

    // MARK: - Content

    private var settingsContent: some View {
        List {
            appLockSection
            convenienceSection
            if lockManager.isPINSet {
                dangerZoneSection
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
            if lockManager.isPINSet && canUseBiometrics {
                Toggle(isOn: Binding(
                    get: { lockManager.isBiometricEnabled },
                    set: { lockManager.isBiometricEnabled = $0 }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: biometricIcon)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(biometricTypeRawValue)로 잠금 해제")
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
        } footer: {
            Text("앱이 백그라운드로 전환되면 자동으로 잠깁니다.")
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
    Text("보안 설정 열기")
        .sheet(isPresented: .constant(true)) {
            SecuritySettingsModal()
        }
}
