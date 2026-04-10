import SwiftUI

struct LockScreenView: View {
    @State private var lockManager = AppLockManager.shared
    @State private var errorMessage: String? = nil
    @State private var isAuthenticating = false

    private var backgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                appIconSection

                appNameSection

                Spacer()

                unlockSection

                Spacer()
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Subviews

    private var appIconSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)

            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white)
        }
        .shadow(color: .blue.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    private var appNameSection: some View {
        VStack(spacing: 8) {
            Text("CryptoTrack")
                .font(.title.bold())

            Text("계속하려면 잠금을 해제하세요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var unlockSection: some View {
        VStack(spacing: 16) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Button {
                Task {
                    await performUnlock()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: biometricIcon)
                        .font(.body.weight(.semibold))
                    Text("잠금 해제")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isAuthenticating)
            .opacity(isAuthenticating ? 0.6 : 1)
        }
    }

    // MARK: - Helpers

    private var biometricIcon: String {
        switch BiometricAuthService.shared.biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .none:
            return "lock.open.fill"
        }
    }

    private func performUnlock() async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let success = try await BiometricAuthService.shared.authenticate()
            if success {
                withAnimation {
                    lockManager.isLocked = false
                }
            }
        } catch let error as BiometricAuthError {
            withAnimation {
                errorMessage = error.errorDescription
            }
        } catch {
            withAnimation {
                errorMessage = "인증 중 오류가 발생했습니다."
            }
        }
    }
}

#Preview {
    LockScreenView()
}
