import SwiftUI

/// 체결 내역 리스트. 일자별로 `Section` 그룹핑되며 각 행은 대시보드와
/// 동일한 `PriceFormatter` + `ExchangeBadge`를 사용한다.
struct OrderListView: View {
    let groupedOrders: [(Date, [Order])]
    let isLoading: Bool
    let progress: Double
    let loadedCount: Int
    let errorMessage: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd (E)"
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
            if groupedOrders.isEmpty && !isLoading {
                emptyState
            } else {
                orderList
            }
            if isLoading {
                progressBar
            }
        }
    }

    // MARK: - Order List

    private var orderList: some View {
        List {
            ForEach(groupedOrders, id: \.0) { date, orders in
                Section {
                    ForEach(orders) { order in
                        orderRow(order)
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

    private func orderRow(_ order: Order) -> some View {
        let currency = order.exchange.quoteCurrency
        return HStack(alignment: .top, spacing: 12) {
            ExchangeBadge(exchange: order.exchange, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(order.symbol)
                        .font(.body.weight(.semibold))
                    sideBadge(order.side)
                    Spacer()
                    Text(timeFormatter.string(from: order.executedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(PriceFormatter.formatPrice(order.price, currency: currency)) × \(PriceFormatter.formatBalance(order.amount))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(PriceFormatter.formatAmount(order.totalValue, currency: currency))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                if order.fee > 0 {
                    Text("수수료 \(PriceFormatter.formatAmount(order.fee, currency: currency))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func sideBadge(_ side: OrderSide) -> some View {
        let isBuy = side == .buy
        let tint: Color = isBuy ? AppColor.bullish : AppColor.bearish
        return Text(isBuy ? "매수" : "매도")
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("조회된 체결 내역이 없습니다")
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
