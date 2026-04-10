import SwiftUI

/// 거래소별 API 키 입력 및 관리 화면입니다.
struct ExchangeSetupView: View {
    let exchange: Exchange
    let settingsViewModel: SettingsViewModel

    @State private var accessKey: String = ""
    @State private var secretKey: String = ""
    @State private var passphrase: String = ""
    @State private var showDeleteConfirmation = false
    @State private var showGuide = false
    @State private var alertMessage: String? = nil
    @State private var showAlert = false
    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed Properties

    private var isSaved: Bool {
        settingsViewModel.savedExchanges.contains(exchange)
    }

    private var connectionStatus: ConnectionStatus {
        settingsViewModel.connectionStatus[exchange] ?? .untested
    }

    private var isTestingConnection: Bool {
        if case .testing = connectionStatus { return true }
        return false
    }

    /// Korbit은 Client ID / Client Secret 레이블 사용
    private var accessKeyLabel: String {
        exchange == .korbit ? "Client ID" : "Access Key"
    }

    private var secretKeyLabel: String {
        exchange == .korbit ? "Client Secret" : "Secret Key"
    }

    private var showPassphraseField: Bool {
        exchange == .okx
    }

    // MARK: - Body

    var body: some View {
        platformContent
            .navigationTitle(exchange.rawValue)
            .sheet(isPresented: $showGuide) {
                if let guide = ExchangeGuide.all[exchange] {
                    APIKeyGuideView(guide: guide)
                }
            }
            .alert("알림", isPresented: $showAlert) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog(
                "\(exchange.rawValue) API 키를 삭제하시겠습니까?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive) {
                    deleteKeys()
                }
                Button("취소", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(macOS)
        ScrollView {
            VStack(spacing: 20) {
                macHeader
                macCredentialsBox
                macActionArea
                if isSaved {
                    macDangerZone
                }
                macFooter
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        #else
        Form {
            guideSection
            credentialsSection
            actionSection
            if isSaved {
                deleteSection
            }
        }
        .inlineNavigationTitle()
        #endif
    }

    // MARK: - macOS Components

    #if os(macOS)
    private var macHeader: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColor.exchange(exchange))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(exchange.rawValue.prefix(1)))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(exchange.rawValue)
                    .font(.title2.bold())
                Text("API 키 설정")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSaved {
                macStatusBadge
            }
        }
    }

    @ViewBuilder
    private var macStatusBadge: some View {
        switch connectionStatus {
        case .untested:
            Capsule()
                .fill(.secondary.opacity(0.15))
                .overlay(
                    HStack(spacing: 4) {
                        Image(systemName: "minus.circle")
                        Text("테스트 전")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                )
                .frame(width: 90, height: 24)
        case .testing:
            Capsule()
                .fill(.blue.opacity(0.15))
                .overlay(
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("테스트 중")
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                )
                .frame(width: 90, height: 24)
        case .success:
            Capsule()
                .fill(.green.opacity(0.15))
                .overlay(
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("연결됨")
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                )
                .frame(width: 90, height: 24)
        case .failed:
            Capsule()
                .fill(.red.opacity(0.15))
                .overlay(
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                        Text("실패")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                )
                .frame(width: 90, height: 24)
        }
    }

    private var macCredentialsBox: some View {
        GroupBox {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text(accessKeyLabel)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    SecureField("입력", text: $accessKey)
                        .textFieldStyle(.roundedBorder)
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text(secretKeyLabel)
                        .foregroundStyle(.secondary)
                    SecureField("입력", text: $secretKey)
                        .textFieldStyle(.roundedBorder)
                }
                if showPassphraseField {
                    GridRow {
                        Text("Passphrase")
                            .foregroundStyle(.secondary)
                        SecureField("입력", text: $passphrase)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("API 키 정보", systemImage: "key.fill")
        }
    }

    private var macActionArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task { await settingsViewModel.testConnection(exchange: exchange) }
                } label: {
                    HStack(spacing: 4) {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        Text("연결 테스트")
                    }
                }
                .disabled(isTestingConnection || !isSaved)

                Button {
                    saveKeys()
                } label: {
                    Text("저장")
                }
                .buttonStyle(.borderedProminent)
                .disabled(accessKey.isEmpty || secretKey.isEmpty)
            }

            if isSaved {
                connectionStatusRow
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColor.secondaryBackground)
                    )
            }
        }
    }

    private var macDangerZone: some View {
        GroupBox {
            HStack {
                Text("저장된 API 키를 Keychain에서 완전히 삭제합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("API 키 삭제")
                }
            }
        } label: {
            Label("위험 영역", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var macFooter: some View {
        VStack(spacing: 8) {
            Button {
                showGuide = true
            } label: {
                Text("API 키 발급 방법 안내")
                    .font(.subheadline)
            }
            .buttonStyle(.link)

            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                Text("API 키는 macOS Keychain에 안전하게 저장됩니다.")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
    #endif

    // MARK: - Sections

    private var guideSection: some View {
        Section {
            Button {
                showGuide = true
            } label: {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.blue)
                    Text("API 키 발급 방법 안내")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var credentialsSection: some View {
        Section {
            HStack {
                Text(accessKeyLabel)
                    .frame(width: 110, alignment: .leading)
                    .foregroundStyle(.secondary)
                SecureField("입력", text: $accessKey)
                    .textContentType(.password)
            }
            HStack {
                Text(secretKeyLabel)
                    .frame(width: 110, alignment: .leading)
                    .foregroundStyle(.secondary)
                SecureField("입력", text: $secretKey)
                    .textContentType(.password)
            }
            if showPassphraseField {
                HStack {
                    Text("Passphrase")
                        .frame(width: 110, alignment: .leading)
                        .foregroundStyle(.secondary)
                    SecureField("입력", text: $passphrase)
                        .textContentType(.password)
                }
            }
        } header: {
            Text("API 키 정보")
        } footer: {
            if exchange == .korbit {
                Text("Korbit OAuth 2.0 인증을 위해 Client ID와 Client Secret을 입력하세요.")
            } else if exchange == .okx {
                Text("OKX API 키, Secret Key, Passphrase를 모두 입력하세요.")
            } else {
                Text("\(exchange.rawValue) API 키를 입력하세요.")
            }
        }
    }

    private var actionSection: some View {
        Section {
            // 연결 테스트 버튼
            Button {
                Task { await settingsViewModel.testConnection(exchange: exchange) }
            } label: {
                HStack {
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.85)
                            .padding(.trailing, 4)
                    }
                    Text("연결 테스트")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isTestingConnection || !isSaved)

            // 연결 상태 표시
            if isSaved {
                connectionStatusRow
            }

            // 저장 버튼
            Button {
                saveKeys()
            } label: {
                Text("저장")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .disabled(accessKey.isEmpty || secretKey.isEmpty)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("API 키 삭제")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        HStack(spacing: 8) {
            switch connectionStatus {
            case .untested:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                Text("테스트 전")
                    .foregroundStyle(.secondary)
            case .testing:
                ProgressView()
                    .scaleEffect(0.8)
                Text("연결 확인 중…")
                    .foregroundStyle(.secondary)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("연결 성공")
                    .foregroundStyle(.green)
            case .failed(let message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
        }
        .font(.subheadline)
    }

    // MARK: - Actions

    private func saveKeys() {
        do {
            try settingsViewModel.saveAPIKeys(
                exchange: exchange,
                accessKey: accessKey,
                secretKey: secretKey,
                passphrase: showPassphraseField ? passphrase : nil
            )
            alertMessage = "API 키가 저장되었습니다."
            showAlert = true
            accessKey = ""
            secretKey = ""
            passphrase = ""
        } catch {
            alertMessage = "저장 실패: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func deleteKeys() {
        do {
            try settingsViewModel.deleteAPIKeys(exchange: exchange)
            dismiss()
        } catch {
            alertMessage = "삭제 실패: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ExchangeSetupView(
            exchange: .upbit,
            settingsViewModel: SettingsViewModel()
        )
    }
}

#Preview("OKX") {
    NavigationStack {
        ExchangeSetupView(
            exchange: .okx,
            settingsViewModel: SettingsViewModel()
        )
    }
}

#Preview("Korbit") {
    NavigationStack {
        ExchangeSetupView(
            exchange: .korbit,
            settingsViewModel: SettingsViewModel()
        )
    }
}
