import SwiftUI

// MARK: - IndicatorType

enum IndicatorType: String, CaseIterable, Sendable {
    case ma = "MA"
    case ema = "EMA"
    case bollingerBands = "BB"
    case rsi = "RSI"
    case macd = "MACD"
    case stochastic = "Stoch"
    case obv = "OBV"

    var displayName: String {
        switch self {
        case .ma:             return "이동평균 (MA)"
        case .ema:            return "지수이동평균 (EMA)"
        case .bollingerBands: return "볼린저 밴드 (BB)"
        case .rsi:            return "RSI"
        case .macd:           return "MACD"
        case .stochastic:     return "스토캐스틱 (Stoch)"
        case .obv:            return "누적거래량 (OBV)"
        }
    }

    var position: IndicatorPosition {
        switch self {
        case .ma, .ema, .bollingerBands: return .overlay
        case .rsi, .macd, .stochastic, .obv: return .subPanel
        }
    }

    /// Default parameters for each indicator type
    var defaultParameters: [String: Double] {
        switch self {
        case .ma:             return ["period": 20]
        case .ema:            return ["period": 20]
        case .bollingerBands: return ["period": 20, "multiplier": 2.0]
        case .rsi:            return ["period": 14]
        case .macd:           return ["fast": 12, "slow": 26, "signal": 9]
        case .stochastic:     return ["period": 14, "smoothK": 3, "smoothD": 3]
        case .obv:            return [:]
        }
    }

    var defaultColor: Color {
        switch self {
        case .ma:             return .orange
        case .ema:            return .blue
        case .bollingerBands: return .purple
        case .rsi:            return .cyan
        case .macd:           return .indigo
        case .stochastic:     return .teal
        case .obv:            return .mint
        }
    }
}

// MARK: - IndicatorPosition

enum IndicatorPosition: Sendable {
    /// Drawn on top of the candlestick chart (MA, EMA, BB)
    case overlay
    /// Drawn in a separate panel below volume bars (RSI, MACD, Stoch, OBV)
    case subPanel
}

// MARK: - IndicatorConfig

struct IndicatorConfig: Identifiable, Sendable {
    let id: String
    let type: IndicatorType
    var parameters: [String: Double]
    var color: Color
    var isVisible: Bool

    var position: IndicatorPosition { type.position }

    init(
        id: String = UUID().uuidString,
        type: IndicatorType,
        parameters: [String: Double]? = nil,
        color: Color? = nil,
        isVisible: Bool = true
    ) {
        self.id = id
        self.type = type
        self.parameters = parameters ?? type.defaultParameters
        self.color = color ?? type.defaultColor
        self.isVisible = isVisible
    }

    /// Convenience label shown in the UI (e.g. "MA (20)")
    var label: String {
        switch type {
        case .ma:
            let p = Int(parameters["period"] ?? 20)
            return "MA (\(p))"
        case .ema:
            let p = Int(parameters["period"] ?? 20)
            return "EMA (\(p))"
        case .bollingerBands:
            let p = Int(parameters["period"] ?? 20)
            let m = parameters["multiplier"] ?? 2.0
            return "BB (\(p), \(String(format: "%.1f", m)))"
        case .rsi:
            let p = Int(parameters["period"] ?? 14)
            return "RSI (\(p))"
        case .macd:
            let fast = Int(parameters["fast"] ?? 12)
            let slow = Int(parameters["slow"] ?? 26)
            let sig  = Int(parameters["signal"] ?? 9)
            return "MACD (\(fast),\(slow),\(sig))"
        case .stochastic:
            let p = Int(parameters["period"] ?? 14)
            return "Stoch (\(p))"
        case .obv:
            return "OBV"
        }
    }
}

// MARK: - IndicatorValue

struct IndicatorValue: Sendable {
    let timestamp: Date
    /// Key-value pairs, e.g. ["ma": 50000] or ["upper": x, "middle": y, "lower": z]
    let values: [String: Double]
}
