import SwiftUI

struct DepositListView: View {
    let groupedDeposits: [(Date, [Deposit])]
    let isLoading: Bool
    let progress: Double
    let loadedCount: Int
    let errorMessage: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
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
                Section(dateFormatter.string(from: date)) {
                    ForEach(deposits) { deposit in
                        depositRow(deposit)
                    }
                }
            }
        }
    }

    private func depositRow(_ deposit: Deposit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(deposit.symbol)
                        .font(.body.bold())
                    Text(deposit.type == .fiat ? "원화" : "코인")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    Spacer()
                    Text(deposit.exchange.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if deposit.type == .fiat {
                        Text("\(deposit.amount, specifier: "%.0f")원")
                            .font(.subheadline)
                    } else {
                        Text("\(deposit.amount, specifier: "%.8g") \(deposit.symbol)")
                            .font(.subheadline)
                    }
                    Spacer()
                    statusBadge(deposit.status)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Status Badge

    private func statusBadge(_ status: DepositStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .completed: return ("완료", .green)
            case .pending: return ("처리중", .orange)
            case .cancelled: return ("취소", .red)
            }
        }()
        return Text(text)
            .font(.caption)
            .foregroundStyle(color)
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
            Text("\(Int(progress * 100))% (\(loadedCount)건 로드됨)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }
}
