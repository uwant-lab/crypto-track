import SwiftUI

/// 입금 내역 리스트. 일자별 `Section` 그룹핑, 대시보드와 동일한
/// `PriceFormatter` + `ExchangeBadge` 사용.
/// 체결 내역과 동일하게 필터 칩, 요약 섹션, 수수료를 표시한다.
struct DepositListView: View {
    let groupedDeposits: [(Date, [Deposit])]
    let isLoading: Bool
    let progress: Double
    let loadedCount: Int
    let progressMessage: String
    let errorMessage: String?
    let summary: [DepositSymbolSummary]
    let totalFiatAmount: Double
    let totalCryptoCount: Int
    let totalFee: Double
    let filteredCount: Int
    let showFiat: Bool
    let showCrypto: Bool
    @Binding var isDepositSummaryExpanded: Bool
    let onToggleType: (DepositType) -> Void

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd (E)"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                errorBanner(error)
            }
            if loadedCount > 0 {
                filterChips
                summarySection
            }
            if groupedDeposits.isEmpty && !isLoading {
                emptyState
            } else {
                depositList
            }
            if isLoading {
                progressBar
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        HStack(spacing: 8) {
            chipButton(label: "원화", isOn: showFiat, color: .blue) {
                onToggleType(.fiat)
            }
            chipButton(label: "코인", isOn: showCrypto, color: .purple) {
                onToggleType(.crypto)
            }
            Spacer()
            Text("총 \(filteredCount)건")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func chipButton(label: String, isOn: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isOn ? color : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isOn ? color.opacity(0.15) : Color.clear)
                    .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.4) : Color.secondary.opacity(0.3), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDepositSummaryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isDepositSummaryExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("요약")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !isDepositSummaryExpanded {
                        if showFiat {
                            Text("원화 \(PriceFormatter.formatAmount(totalFiatAmount, currency: .krw))")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        if showCrypto {
                            Text("코인 \(totalCryptoCount)건")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }
                        if totalFee > 0 {
                            Text("수수료 \(PriceFormatter.formatAmount(totalFee, currency: .krw))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
            .buttonStyle(.plain)

            if isDepositSummaryExpanded {
                summaryTable
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
        }
    }

    private var summaryTable: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 0) {
                Text("심볼").frame(width: 60, alignment: .leading)
                if showFiat {
                    Text("원화 입금").frame(maxWidth: .infinity, alignment: .trailing)
                }
                if showCrypto {
                    Text("코인 수량").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("건수").frame(width: 50, alignment: .trailing)
                }
                if totalFee > 0 {
                    Text("수수료").frame(width: 90, alignment: .trailing)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 4)

            Divider()

            // 심볼별 행
            ForEach(summary) { row in
                HStack(spacing: 0) {
                    Text(row.symbol)
                        .font(.caption.weight(.semibold))
                        .frame(width: 60, alignment: .leading)
                    if showFiat {
                        Text(row.fiatAmount > 0 ? PriceFormatter.formatAmount(row.fiatAmount, currency: .krw) : "-")
                            .foregroundStyle(row.fiatAmount > 0 ? .blue : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if showCrypto {
                        Text(row.cryptoAmount > 0 ? PriceFormatter.formatBalance(row.cryptoAmount) : "-")
                            .foregroundStyle(row.cryptoAmount > 0 ? .purple : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(row.cryptoCount > 0 ? "\(row.cryptoCount)" : "-")
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    if totalFee > 0 {
                        Text(row.fee > 0 ? PriceFormatter.formatAmount(row.fee, currency: .krw) : "-")
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal)
                .padding(.vertical, 3)

                Divider().padding(.horizontal)
            }

            // 합계 행
            HStack(spacing: 0) {
                Text("합계")
                    .font(.caption.weight(.bold))
                    .frame(width: 60, alignment: .leading)
                if showFiat {
                    Text(PriceFormatter.formatAmount(totalFiatAmount, currency: .krw))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if showCrypto {
                    Text("").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("\(totalCryptoCount)")
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
                if totalFee > 0 {
                    Text(PriceFormatter.formatAmount(totalFee, currency: .krw))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }
            }
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Deposit List

    private var depositList: some View {
        List {
            ForEach(groupedDeposits, id: \.0) { date, deposits in
                Section {
                    ForEach(deposits) { deposit in
                        depositRow(deposit)
                    }
                } header: {
                    Text(dateFormatter.string(from: date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
    }

    private func depositRow(_ deposit: Deposit) -> some View {
        let currency = deposit.exchange.quoteCurrency
        return HStack(alignment: .top, spacing: 12) {
            ExchangeBadge(exchange: deposit.exchange, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(deposit.symbol)
                        .font(.body.weight(.semibold))
                    typeBadge(deposit.type)
                    statusBadge(deposit.status)
                    Spacer()
                    Text(timeFormatter.string(from: deposit.completedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(alignment: .firstTextBaseline) {
                    Spacer()
                    if deposit.type == .fiat {
                        Text(PriceFormatter.formatAmount(deposit.amount, currency: currency))
                    } else {
                        Text("\(PriceFormatter.formatBalance(deposit.amount)) \(deposit.symbol)")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                if deposit.fee > 0 {
                    Text("수수료 \(PriceFormatter.formatAmount(deposit.fee, currency: currency))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let txId = deposit.txId, !txId.isEmpty {
                    Text(txId)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func typeBadge(_ type: DepositType) -> some View {
        let text = type == .fiat ? "원화" : "코인"
        let tint: Color = type == .fiat ? .blue : .purple
        return Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func statusBadge(_ status: DepositStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .completed: return ("완료", .green)
            case .pending:   return ("처리중", .orange)
            case .cancelled: return ("취소", .red)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("조회된 입금 내역이 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress

    private var progressBar: some View {
        VStack(spacing: 6) {
            ProgressView(value: progress)
            if !progressMessage.isEmpty {
                Text(progressMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(Int(progress * 100))% (\(loadedCount)건 로드됨)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding()
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}
