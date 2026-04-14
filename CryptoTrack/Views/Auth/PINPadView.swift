// CryptoTrack/Views/Auth/PINPadView.swift
import SwiftUI

// MARK: - PIN Dots Indicator

struct PINDotsView: View {
    let enteredCount: Int
    let totalDigits: Int
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<totalDigits, id: \.self) { index in
                Circle()
                    .fill(dotFill(at: index))
                    .frame(width: 14, height: 14)
                    .overlay {
                        if index >= enteredCount && !isError {
                            Circle()
                                .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                        }
                    }
            }
        }
    }

    private func dotFill(at index: Int) -> Color {
        if isError { return .red }
        return index < enteredCount ? .accentColor : .clear
    }
}

// MARK: - Number Pad

struct PINPadView: View {
    let onNumberTap: (Int) -> Void
    let onDeleteTap: () -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
            spacing: 10
        ) {
            ForEach(1...9, id: \.self) { number in
                numberButton(number)
            }
            Color.clear.frame(height: 52)
            numberButton(0)
            deleteButton
        }
        .frame(maxWidth: 240)
    }

    private func numberButton(_ number: Int) -> some View {
        Button {
            onNumberTap(number)
        } label: {
            Text("\(number)")
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppColor.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button {
            onDeleteTap()
        } label: {
            Image(systemName: "delete.backward")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("PINPad") {
    VStack(spacing: 32) {
        PINDotsView(enteredCount: 2, totalDigits: 4)
        PINDotsView(enteredCount: 4, totalDigits: 4, isError: true)
        PINPadView(onNumberTap: { _ in }, onDeleteTap: {})
    }
    .padding()
}
