import Foundation

/// 모든 숫자를 최대 8자리 소수 정밀도로 표현한다.
/// Trailing zero는 생략한다 (`12.5` 는 `12.5000000`이 아니라 `12.5`).
///
/// 통화별 반올림(KRW 정수 등)은 의도적으로 하지 않는다 — 저단가 코인의
/// 가격(`$0.00001234`)이나 KRW 합산에서 발생하는 소수점이 잘리지 않도록.
enum PriceFormatter {

    /// 화폐/금액/단가/수익 등 범용 숫자 포매터. 0 ~ 8자리 가변.
    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 8
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    /// "₩ 12,847,300.52" / "$ 0.00001234"
    /// 통화 단가·총액 모두 이 함수로 표기한다.
    static func formatPrice(_ value: Double, currency: QuoteCurrency) -> String {
        let number = decimalFormatter.string(from: NSNumber(value: value)) ?? "0"
        return "\(currency.symbol) \(number)"
    }

    /// 통화 총액 표기. `formatPrice`와 의미상 별칭이지만 호출부 의도를 드러내기 위해 유지.
    static func formatAmount(_ value: Double, currency: QuoteCurrency) -> String {
        formatPrice(value, currency: currency)
    }

    /// "+₩ 12,847,300.52" / "-$ 3.25" — 수익 금액처럼 부호가 필요한 금액.
    static func formatSignedAmount(_ value: Double, currency: QuoteCurrency) -> String {
        let sign = value >= 0 ? "+" : "-"
        let number = decimalFormatter.string(from: NSNumber(value: abs(value))) ?? "0"
        return "\(sign)\(currency.symbol) \(number)"
    }

    /// 보유량 (통화 기호 없음, 0~8자리 가변).
    static func formatBalance(_ value: Double) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// "+10.74%" / "-3.2%" — 최대 8자리.
    static func formatRate(_ rate: Double) -> String {
        let sign = rate >= 0 ? "+" : "-"
        let number = decimalFormatter.string(from: NSNumber(value: abs(rate))) ?? "0"
        return "\(sign)\(number)%"
    }
}
