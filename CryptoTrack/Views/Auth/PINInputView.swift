// CryptoTrack/Views/Auth/PINInputView.swift
import SwiftUI

enum PINFlowMode: Hashable {
    case setup
    case change
    case remove
}

struct PINInputView: View {
    let mode: PINFlowMode
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    @State private var step: Step = .initial
    @State private var newPIN: String = ""
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var alertMessage: String?
    @State private var showAlert = false

    private let pinService = PINService.shared
    private let pinLength = 4

    private enum Step {
        case initial
        case enterNew
        case confirm
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            instructionSection
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
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
        .navigationTitle(titleText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
        }
        .alert("오류", isPresented: $showAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Text

    private var titleText: String {
        switch mode {
        case .setup: "PIN 설정"
        case .change: "PIN 변경"
        case .remove: "PIN 해제"
        }
    }

    private var instructionText: String {
        switch (mode, step) {
        case (.setup, .initial): "새로운 PIN을 입력하세요"
        case (.setup, .confirm): "PIN을 다시 입력하세요"
        case (.change, .initial): "현재 PIN을 입력하세요"
        case (.change, .enterNew): "새로운 PIN을 입력하세요"
        case (.change, .confirm): "PIN을 다시 입력하세요"
        case (.remove, .initial): "현재 PIN을 입력하세요"
        default: ""
        }
    }

    private var subtitleText: String {
        switch (mode, step) {
        case (.setup, .initial): "4자리 숫자"
        case (.setup, .confirm): "확인을 위해 한 번 더 입력해주세요"
        case (.change, .initial): "변경을 위해 현재 PIN을 입력해주세요"
        case (.change, .enterNew): "4자리 숫자"
        case (.change, .confirm): "확인을 위해 한 번 더 입력해주세요"
        case (.remove, .initial): "해제를 위해 현재 PIN을 입력해주세요"
        default: ""
        }
    }

    private var instructionSection: some View {
        VStack(spacing: 8) {
            Text(instructionText)
                .font(.headline)
            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Input

    private func handleNumberInput(_ number: Int) {
        guard pin.count < pinLength else { return }
        withAnimation { errorMessage = nil }
        pin += "\(number)"

        if pin.count == pinLength {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                processPIN()
            }
        }
    }

    private func handleDelete() {
        guard !pin.isEmpty else { return }
        withAnimation { errorMessage = nil }
        pin.removeLast()
    }

    // MARK: - Flow Logic

    private func processPIN() {
        switch (mode, step) {
        case (.setup, .initial):
            newPIN = pin
            pin = ""
            step = .confirm

        case (.setup, .confirm):
            if pin == newPIN {
                savePIN(pin)
            } else {
                showError("PIN이 일치하지 않습니다")
                newPIN = ""
                step = .initial
            }

        case (.change, .initial):
            if pinService.verifyPIN(pin) {
                pin = ""
                step = .enterNew
            } else {
                showError("PIN이 일치하지 않습니다")
            }

        case (.change, .enterNew):
            newPIN = pin
            pin = ""
            step = .confirm

        case (.change, .confirm):
            if pin == newPIN {
                savePIN(pin)
            } else {
                showError("PIN이 일치하지 않습니다")
                newPIN = ""
                step = .enterNew
            }

        case (.remove, .initial):
            if pinService.verifyPIN(pin) {
                do {
                    try pinService.deletePIN()
                    onComplete()
                } catch {
                    alertMessage = "PIN 해제에 실패했습니다. 다시 시도해주세요."
                    showAlert = true
                    pin = ""
                }
            } else {
                showError("PIN이 일치하지 않습니다")
            }

        default:
            break
        }
    }

    private func savePIN(_ value: String) {
        do {
            try pinService.setPIN(value)
            onComplete()
        } catch {
            let action = mode == .setup ? "설정" : "변경"
            alertMessage = "PIN \(action)에 실패했습니다. 다시 시도해주세요."
            showAlert = true
            resetFlow()
        }
    }

    private func showError(_ message: String) {
        pin = ""
        withAnimation { errorMessage = message }
        withAnimation(.default.speed(6).repeatCount(4, autoreverses: true)) {
            shakeOffset = 8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation { shakeOffset = 0 }
        }
    }

    private func resetFlow() {
        pin = ""
        newPIN = ""
        step = .initial
        errorMessage = nil
    }
}
