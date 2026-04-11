// CryptoTrack/Views/Dashboard/Components/ProfitBadge.swift
import SwiftUI

/// 수익률(%)과 손익 금액을 표시하는 작은 배지.
struct ProfitBadge: View {
    let rate: Double
    let profit: Double?       // nil이면 금액 미표시 (요약 카드에서는 표시, 테이블 셀에서는 숨김)
    let currency: QuoteCurrency?
    let colorMode: PriceColorMode

    init(
        rate: Double,
        profit: Double? = nil,
        currency: QuoteCurrency? = nil,
        colorMode: PriceColorMode
    ) {
        self.rate = rate
        self.profit = profit
        self.currency = currency
        self.colorMode = colorMode
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(PriceFormatter.formatRate(rate))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PriceColor.color(for: rate, mode: colorMode))
                .monospacedDigit()
            if let profit, let currency {
                Text(PriceFormatter.formatPrice(profit, currency: currency))
                    .font(.caption2)
                    .foregroundStyle(PriceColor.color(for: profit, mode: colorMode))
                    .monospacedDigit()
            }
        }
    }
}
