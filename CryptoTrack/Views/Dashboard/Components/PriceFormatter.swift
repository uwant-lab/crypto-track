import Foundation

/// 통화별 포매팅 규칙:
/// - KRW: 정수 (소수점 없음)
/// - USDT: 최대 8자리 소수 (trailing zero 생략)
/// - 수익률(%): 소수 2자리 고정
enum PriceFormatter {

    /// USD 등 소수점이 필요한 통화용 포매터 (0~8자리 가변).
    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 8
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    /// KRW 전용 포매터 (정수, 소수점 없음).
    private static let integerFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    /// 수익률 전용 포매터 (소수 2자리 고정).
    private static let rateFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    /// 소액(< 1) 전용 포매터 (소수 3자리 고정).
    private static let smallPriceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 8
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    private static func formatter(for currency: QuoteCurrency, value: Double = 1) -> NumberFormatter {
        if abs(value) < 1 && abs(value) > 0 { return smallPriceFormatter }
        switch currency {
        case .krw: return integerFormatter
        case .usdt: return decimalFormatter
        }
    }

    /// "₩ 12,847,300" / "₩ 0.350" / "$ 0.00001234"
    static func formatPrice(_ value: Double, currency: QuoteCurrency) -> String {
        let number = formatter(for: currency, value: value).string(from: NSNumber(value: value)) ?? "0"
        return "\(currency.symbol) \(number)"
    }

    /// 통화 총액 표기. `formatPrice`와 의미상 별칭이지만 호출부 의도를 드러내기 위해 유지.
    static func formatAmount(_ value: Double, currency: QuoteCurrency) -> String {
        formatPrice(value, currency: currency)
    }

    /// "+₩ 12,847,300" / "-$ 3.25" — 수익 금액처럼 부호가 필요한 금액.
    static func formatSignedAmount(_ value: Double, currency: QuoteCurrency) -> String {
        let sign = value >= 0 ? "+" : "-"
        let number = formatter(for: currency, value: value).string(from: NSNumber(value: abs(value))) ?? "0"
        return "\(sign)\(currency.symbol) \(number)"
    }

    /// 보유량 (통화 기호 없음, 0~8자리 가변).
    static func formatBalance(_ value: Double) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// "+10.74%" / "-3.20%" — 소수 2자리 고정.
    static func formatRate(_ rate: Double) -> String {
        let sign = rate >= 0 ? "+" : "-"
        let number = rateFormatter.string(from: NSNumber(value: abs(rate))) ?? "0.00"
        return "\(sign)\(number)%"
    }

    /// "~+10.74%" — 사용자가 평단가를 수정한 경우 근사치 표시.
    static func formatApproxRate(_ rate: Double) -> String {
        "~\(formatRate(rate))"
    }

    /// 사용자가 수정한 평단가 표시용. KRW도 소수 2자리까지 표시.
    /// "₩ 55,000,000.50" / "$ 0.00001234"
    static func formatModifiedPrice(_ value: Double, currency: QuoteCurrency) -> String {
        let fmt: NumberFormatter = currency == .krw ? rateFormatter : decimalFormatter
        let number = fmt.string(from: NSNumber(value: value)) ?? "0"
        return "\(currency.symbol) \(number)"
    }
}
