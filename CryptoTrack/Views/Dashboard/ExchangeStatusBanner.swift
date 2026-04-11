// CryptoTrack/Views/Dashboard/ExchangeStatusBanner.swift
import SwiftUI

/// 일부 거래소만 fetch 실패했을 때 표시하는 경고 배너.
///
/// 두 종류의 실패를 구분해 보여준다:
/// 1. **자산(balance) 조회 실패** — 해당 거래소의 어떤 코인도 대시보드에
///    표시되지 않음.
/// 2. **시세 조회 실패** — 자산은 받았지만 현재가/평가금액이 "—"로 뜨는
///    상태. 이 케이스는 사용자가 "왜 현재가가 안 보이지?"하고 의아해하는
///    전형적인 시나리오이므로 반드시 노출해야 한다.
struct ExchangeStatusBanner: View {
    let statuses: [ExchangeFetchStatus]

    private var assetFailures: [ExchangeFetchStatus] {
        statuses.filter { $0.status == .failed }
    }

    /// 자산은 성공했는데 시세만 실패한 케이스. 자산 자체가 실패한 행은
    /// 위의 `assetFailures`에서 이미 보여주므로 여기서는 제외한다.
    private var tickerOnlyFailures: [ExchangeFetchStatus] {
        statuses.filter { $0.status != .failed && $0.hasTickerFailure }
    }

    var body: some View {
        if assetFailures.isEmpty && tickerOnlyFailures.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !assetFailures.isEmpty {
                    failureBlock(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        headline: "\(assetFailures.count)개 거래소 자산 갱신 실패",
                        detail: firstDetail(from: assetFailures) { $0.lastError }
                    )
                }
                if !tickerOnlyFailures.isEmpty {
                    failureBlock(
                        icon: "chart.line.downtrend.xyaxis",
                        tint: .yellow,
                        headline: "\(tickerOnlyFailures.count)개 거래소 시세 갱신 실패 — 현재가/평가금액 표시 안 됨",
                        detail: firstDetail(from: tickerOnlyFailures) { $0.tickerError }
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.12))
            )
        }
    }

    @ViewBuilder
    private func failureBlock(icon: String, tint: Color, headline: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.caption.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func firstDetail(from failures: [ExchangeFetchStatus], error: (ExchangeFetchStatus) -> String?) -> String? {
        guard let first = failures.first, let message = error(first) else { return nil }
        return "\(first.id.rawValue): \(message)"
    }
}

#Preview("asset + ticker failure") {
    ExchangeStatusBanner(statuses: [
        .init(id: .upbit, status: .success, lastError: nil, tickerError: nil),
        .init(id: .bithumb, status: .failed, lastError: "401 Unauthorized", tickerError: nil),
        .init(id: .binance, status: .success, lastError: nil, tickerError: "The request timed out."),
    ])
    .padding()
}

#Preview("ticker only") {
    ExchangeStatusBanner(statuses: [
        .init(id: .upbit, status: .success, lastError: nil, tickerError: nil),
        .init(id: .binance, status: .success, lastError: nil, tickerError: "The request timed out."),
    ])
    .padding()
}
