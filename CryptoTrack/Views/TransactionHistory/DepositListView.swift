import SwiftUI

/// 입금 내역 리스트. 일자별 `Section` 그룹핑, 대시보드와 동일한
/// `PriceFormatter` + `ExchangeBadge` 사용.
struct DepositListView: View {
    let groupedDeposits: [(Date, [Deposit])]
    let isLoading: Bool
    let progress: Double
    let loadedCount: Int
    let progressMessage: String
    let errorMessage: String?

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
        HStack(alignment: .top, spacing: 12) {
            ExchangeBadge(exchange: deposit.exchange, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(deposit.symbol)
                        .font(.body.weight(.semibold))
                    typeBadge(deposit.type)
                    Spacer()
                    Text(timeFormatter.string(from: deposit.completedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(alignment: .firstTextBaseline) {
                    amountText(for: deposit)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    Spacer()
                    statusBadge(deposit.status)
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

    @ViewBuilder
    private func amountText(for deposit: Deposit) -> some View {
        if deposit.type == .fiat {
            Text(PriceFormatter.formatAmount(deposit.amount, currency: deposit.exchange.quoteCurrency))
        } else {
            Text("\(PriceFormatter.formatBalance(deposit.amount)) \(deposit.symbol)")
        }
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
