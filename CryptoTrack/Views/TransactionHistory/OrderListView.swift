import SwiftUI

struct OrderListView: View {
    let groupedOrders: [(Date, [Order])]
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
                Section(dateFormatter.string(from: date)) {
                    ForEach(orders) { order in
                        orderRow(order)
                    }
                }
            }
        }
    }

    private func orderRow(_ order: Order) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(order.symbol)
                        .font(.body.bold())
                    Text(order.side == .buy ? "매수" : "매도")
                        .font(.caption.bold())
                        .foregroundStyle(order.side == .buy ? AppColor.bullish : AppColor.bearish)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (order.side == .buy ? AppColor.bullish : AppColor.bearish).opacity(0.1)
                        )
                        .clipShape(Capsule())
                    Spacer()
                    Text(order.exchange.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("\(order.price, specifier: "%.0f")원 x \(order.amount, specifier: "%.8g")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(order.totalValue, specifier: "%.0f")원")
                        .font(.subheadline.bold())
                }
            }
            .padding(.vertical, 2)
        }
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
