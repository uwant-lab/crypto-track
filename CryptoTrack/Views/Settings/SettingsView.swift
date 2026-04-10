import SwiftUI

/// 거래소 API 키 관리 설정 화면입니다.
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

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

// MARK: - Preview

#Preview {
    SettingsView()
}
