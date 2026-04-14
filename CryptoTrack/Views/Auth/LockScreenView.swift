import SwiftUI

struct LockScreenView: View {
    @State private var lockManager = AppLockManager.shared
    @State private var pin: String = ""
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var isAuthenticating = false

    private let authService = BiometricAuthService.shared
    private let pinLength = 4

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                appIconSection
                    .padding(.bottom, 24)

                Text("PIN을 입력하세요")
                    .font(.headline)
                    .padding(.bottom, 24)

                PINDotsView(
                    enteredCount: pin.count,
                    totalDigits: pinLength,
                    isError: errorMessage != nil
                )
                .offset(x: shakeOffset)
                .padding(.bottom, 8)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }

                Spacer()

                PINPadView(
                    onNumberTap: { handleNumberInput($0) },
                    onDeleteTap: { handleDelete() }
                )

                if lockManager.isBiometricEnabled && authService.canUseBiometrics() {
                    Button {
                        Task { await attemptBiometric() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: biometricIcon)
                            Text("\(authService.biometricType.rawValue)로 해제")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    }
                    .disabled(isAuthenticating)
                    .padding(.top, 20)
                }

                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .task {
            if lockManager.isBiometricEnabled && authService.canUseBiometrics() {
                await attemptBiometric()
            }
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
                .frame(width: 80, height: 80)

            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
        }
        .shadow(color: .blue.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    // MARK: - Input

    private func handleNumberInput(_ number: Int) {
        guard pin.count < pinLength else { return }
        withAnimation { errorMessage = nil }
        pin += String(number)

        if pin.count == pinLength {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                verifyPIN()
            }
        }
    }

    private func handleDelete() {
        guard !pin.isEmpty else { return }
        withAnimation { errorMessage = nil }
        pin.removeLast()
    }

    // MARK: - Auth

    private func verifyPIN() {
        if lockManager.unlockWithPIN(pin) {
            // 성공 — AppLockManager가 isLocked = false 처리
        } else {
            pin = ""
            withAnimation { errorMessage = "PIN이 일치하지 않습니다" }
            withAnimation(.default.speed(6).repeatCount(4, autoreverses: true)) {
                shakeOffset = 8
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation { shakeOffset = 0 }
            }
        }
    }

    private func attemptBiometric() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        _ = await lockManager.unlockWithBiometrics()
    }

    private var biometricIcon: String {
        switch authService.biometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .none: "lock.open.fill"
        }
    }
}

#Preview {
    LockScreenView()
}
