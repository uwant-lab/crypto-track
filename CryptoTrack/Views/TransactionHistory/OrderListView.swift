import SwiftUI

/// 체결 내역 리스트. 일자별로 `Section` 그룹핑되며 각 행은 대시보드와
/// 동일한 `PriceFormatter` + `ExchangeBadge`를 사용한다.
struct OrderListView: View {
    let groupedOrders: [(Date, [Order])]
    let isLoading: Bool
    let progress: Double
    let loadedCount: Int
    let progressMessage: String
    let errorMessage: String?
    let summary: [OrderSymbolSummary]
    let totalBuyValue: Double
    let totalSellValue: Double
    let totalFee: Double
    let filteredCount: Int
    let showBuy: Bool
    let showSell: Bool
    @Binding var isSummaryExpanded: Bool
    let onToggleSide: (OrderSide) -> Void

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
            if !groupedOrders.isEmpty || !summary.isEmpty {
                filterChips
                summarySection
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

    // MARK: - Filter Chips

    private var filterChips: some View {
        HStack(spacing: 8) {
            chipButton(label: "매수", isOn: showBuy, color: AppColor.bullish) {
                onToggleSide(.buy)
            }
            chipButton(label: "매도", isOn: showSell, color: AppColor.bearish) {
                onToggleSide(.sell)
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
            // 접힌 상태 바
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSummaryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSummaryExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("요약")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !isSummaryExpanded {
                        if showBuy {
                            Text("매수 \(PriceFormatter.formatAmount(totalBuyValue, currency: .krw))")
                                .font(.caption)
                                .foregroundStyle(AppColor.bullish)
                        }
                        if showSell {
                            Text("매도 \(PriceFormatter.formatAmount(totalSellValue, currency: .krw))")
                                .font(.caption)
                                .foregroundStyle(AppColor.bearish)
                        }
                        Text("수수료 \(PriceFormatter.formatAmount(totalFee, currency: .krw))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
            .buttonStyle(.plain)

            // 펼친 상태 테이블
            if isSummaryExpanded {
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
                if showBuy {
                    Text("매수 수량").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("매수 금액").frame(maxWidth: .infinity, alignment: .trailing)
                }
                if showSell {
                    Text("매도 수량").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("매도 금액").frame(maxWidth: .infinity, alignment: .trailing)
                }
                Text("수수료").frame(width: 90, alignment: .trailing)
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
                    if showBuy {
                        Text(PriceFormatter.formatBalance(row.buyAmount))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(PriceFormatter.formatAmount(row.buyTotal, currency: .krw))
                            .foregroundStyle(AppColor.bullish)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if showSell {
                        Text(PriceFormatter.formatBalance(row.sellAmount))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(PriceFormatter.formatAmount(row.sellTotal, currency: .krw))
                            .foregroundStyle(AppColor.bearish)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Text(PriceFormatter.formatAmount(row.fee, currency: .krw))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .trailing)
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
                if showBuy {
                    Text("").frame(maxWidth: .infinity, alignment: .trailing)
                    Text(PriceFormatter.formatAmount(totalBuyValue, currency: .krw))
                        .foregroundStyle(AppColor.bullish)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if showSell {
                    Text("").frame(maxWidth: .infinity, alignment: .trailing)
                    Text(PriceFormatter.formatAmount(totalSellValue, currency: .krw))
                        .foregroundStyle(AppColor.bearish)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Text(PriceFormatter.formatAmount(totalFee, currency: .krw))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
            }
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .padding(.bottom, 4)
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
