import SwiftUI

/// 거래소별 API 키 발급 절차를 안내하는 시트 뷰
struct APIKeyGuideView: View {
    let guide: ExchangeGuide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    stepsSection
                    notesSection
                    if let url = guide.guideURL {
                        linkSection(url: url)
                    }
                }
                .padding(20)
            }
            .background(.background)
            .navigationTitle("API 키 발급 안내")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            exchangeIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(guide.displayName)
                    .font(.title2.bold())
                Text("API 키 발급 방법")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private var exchangeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(exchangeColor.opacity(0.15))
                .frame(width: 48, height: 48)
            Text(String(guide.displayName.prefix(1)))
                .font(.title2.bold())
                .foregroundStyle(exchangeColor)
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "발급 절차", icon: "list.number")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    stepRow(number: index + 1, text: step, isLast: index == guide.steps.count - 1)
                }
            }
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func stepRow(number: Int, text: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(exchangeColor)
                    .frame(width: 26, height: 26)
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, 54)
            }
        }
    }

    // MARK: - Important Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "주의사항", icon: "exclamationmark.shield.fill")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(guide.importantNotes.enumerated()), id: \.offset) { index, note in
                    noteRow(text: note, isLast: index == guide.importantNotes.count - 1)
                }
            }
            .background(Color.red.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func noteRow(text: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 2)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, 42)
            }
        }
    }

    // MARK: - Link

    private func linkSection(url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.body)
                Text("거래소에서 직접 발급하기")
                    .font(.callout.bold())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(exchangeColor.opacity(0.1))
            .foregroundStyle(exchangeColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .padding(.bottom, 10)
    }

    private var exchangeColor: Color {
        switch guide.exchange {
        case .upbit: .blue
        case .binance: .yellow
        case .bithumb: .orange
        case .bybit: .purple
        case .coinone: .green
        case .korbit: .cyan
        case .okx: .indigo
        }
    }
}

// MARK: - Needed Fields Display

/// API 키 입력 필드에서 사용할 라벨 정보를 제공하는 뷰
struct APIKeyFieldInfo: View {
    let guide: ExchangeGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(guide.apiKeyLabels.accessKey)
            fieldLabel(guide.apiKeyLabels.secretKey)
            if let passphrase = guide.apiKeyLabels.passphrase {
                fieldLabel(passphrase)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func fieldLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "key.fill")
                .font(.caption2)
            Text(text)
        }
    }
}

#Preview("업비트 가이드") {
    APIKeyGuideView(guide: .upbit)
}

#Preview("OKX 가이드") {
    APIKeyGuideView(guide: .okx)
}
