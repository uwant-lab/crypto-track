import Foundation

/// 통화별 가격 표시 포맷.
enum PriceFormatter {

    private static let krwFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        f.groupingSeparator = ","
        return f
    }()

    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        return f
    }()

    private static let balanceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 8
        return f
    }()

    /// "₩ 12,847,300" 또는 "$ 3,247.50"
    static func formatPrice(_ value: Double, currency: QuoteCurrency) -> String {
        let formatter = currency == .krw ? krwFormatter : usdFormatter
        let number = formatter.string(from: NSNumber(value: value)) ?? "0"
        return "\(currency.symbol) \(number)"
    }

    /// 보유량(소수점 자릿수 가변)
    static func formatBalance(_ value: Double) -> String {
        balanceFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// "+10.74%" / "-3.20%"
    static func formatRate(_ rate: Double) -> String {
        let sign = rate >= 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", rate)
    }
}
