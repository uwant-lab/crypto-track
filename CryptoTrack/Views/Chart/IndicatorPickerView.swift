import SwiftUI

/// Sheet/popover for adding, removing, and configuring technical indicators.
struct IndicatorPickerView: View {
    @Bindable var viewModel: ChartViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Active indicators section
                if !viewModel.activeIndicators.isEmpty {
                    Section("활성 지표") {
                        ForEach(viewModel.activeIndicators) { config in
                            ActiveIndicatorRow(
                                config: config,
                                onRemove: { viewModel.removeIndicator(id: config.id) },
                                onToggleVisibility: {
                                    viewModel.toggleIndicatorVisibility(id: config.id)
                                }
                            )
                        }
                    }
                }

                // Available indicators section
                Section("지표 추가") {
                    ForEach(IndicatorType.allCases, id: \.self) { type in
                        AddIndicatorRow(
                            type: type,
                            isActive: viewModel.activeIndicators.contains { $0.type == type },
                            onAdd: { viewModel.addIndicator(type) }
                        )
                    }
                }
            }
            .navigationTitle("기술적 지표")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Active Indicator Row

private struct ActiveIndicatorRow: View {
    let config: IndicatorConfig
    let onRemove: () -> Void
    let onToggleVisibility: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Color swatch
            Circle()
                .fill(config.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.label)
                    .font(.subheadline)
                    .foregroundStyle(config.isVisible ? .primary : .secondary)
                Text(config.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Visibility toggle
            Button {
                onToggleVisibility()
            } label: {
                Image(systemName: config.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Remove button
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Indicator Row

private struct AddIndicatorRow: View {
    let type: IndicatorType
    let isActive: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(type.defaultColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.rawValue)
                    .font(.subheadline)
                Text(type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Position badge
            Text(type.position == .overlay ? "오버레이" : "서브패널")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(type.position == .overlay
                        ? Color.blue.opacity(0.15)
                        : Color.purple.opacity(0.15))
                )
                .foregroundStyle(type.position == .overlay ? .blue : .purple)

            Button {
                onAdd()
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isActive ? .green : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isActive)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    let vm = ChartViewModel.preview
    IndicatorPickerView(viewModel: vm)
}
