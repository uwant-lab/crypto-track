// CryptoTrack/Views/Dashboard/ExchangeStatusBanner.swift
import SwiftUI

/// 일부 거래소만 fetch 실패했을 때 표시하는 경고 배너.
struct ExchangeStatusBanner: View {
    let statuses: [ExchangeFetchStatus]

    private var failedStatuses: [ExchangeFetchStatus] {
        statuses.filter { $0.status == .failed }
    }

    var body: some View {
        if failedStatuses.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headlineText)
                        .font(.caption.weight(.semibold))
                    if let first = failedStatuses.first, let err = first.lastError {
                        Text("\(first.id.rawValue): \(err)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.15))
            )
        }
    }

    private var headlineText: String {
        let count = failedStatuses.count
        return "\(count)개 거래소 갱신 실패"
    }
}

#Preview {
    ExchangeStatusBanner(statuses: [
        .init(id: .upbit, status: .success, lastError: nil),
        .init(id: .bithumb, status: .failed, lastError: "401 Unauthorized"),
    ])
    .padding()
}
