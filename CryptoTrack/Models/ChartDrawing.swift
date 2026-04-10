import SwiftUI

// MARK: - Drawing Type

enum DrawingType: String, Codable, CaseIterable, Sendable {
    case trendLine = "추세선"
    case horizontalLine = "수평선"
    case verticalLine = "수직선"
    case ray = "레이"
    case fibonacciRetracement = "피보나치 되돌림"
    case fibonacciExtension = "피보나치 확장"
    case rectangle = "사각형"
    case parallelChannel = "평행 채널"
    case textLabel = "텍스트"
    case priceLabel = "가격 라벨"

    var systemImage: String {
        switch self {
        case .trendLine: "line.diagonal"
        case .horizontalLine: "minus"
        case .verticalLine: "line.vertical.dashed"
        case .ray: "arrow.right"
        case .fibonacciRetracement: "chart.bar.doc.horizontal"
        case .fibonacciExtension: "chart.line.uptrend.xyaxis"
        case .rectangle: "rectangle"
        case .parallelChannel: "rectangle.split.1x2"
        case .textLabel: "textformat"
        case .priceLabel: "tag"
        }
    }

    /// Minimum number of anchor points required
    var requiredPoints: Int {
        switch self {
        case .horizontalLine, .verticalLine, .textLabel, .priceLabel: return 1
        case .trendLine, .ray, .fibonacciRetracement, .fibonacciExtension, .rectangle: return 2
        case .parallelChannel: return 3
        }
    }
}

// MARK: - Drawing Point

struct DrawingPoint: Codable, Sendable {
    let price: Double
    let timestamp: Date
}

// MARK: - Codable Color

struct CodableColor: Codable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.red = Double(resolved.red)
        self.green = Double(resolved.green)
        self.blue = Double(resolved.blue)
        self.opacity = Double(resolved.opacity)
    }

    static let blue = CodableColor(red: 0.0, green: 0.478, blue: 1.0)
    static let red = CodableColor(red: 1.0, green: 0.231, blue: 0.188)
    static let green = CodableColor(red: 0.204, green: 0.78, blue: 0.349)
    static let orange = CodableColor(red: 1.0, green: 0.584, blue: 0.0)
    static let white = CodableColor(red: 1.0, green: 1.0, blue: 1.0)
}

// MARK: - Chart Drawing

struct ChartDrawing: Identifiable, Codable, Sendable {
    let id: String
    let type: DrawingType
    var points: [DrawingPoint]
    var color: CodableColor
    var lineWidth: Double
    var isVisible: Bool
    var text: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        type: DrawingType,
        points: [DrawingPoint] = [],
        color: CodableColor = .blue,
        lineWidth: Double = 1.5,
        isVisible: Bool = true,
        text: String? = nil
    ) {
        self.id = id
        self.type = type
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.isVisible = isVisible
        self.text = text
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isComplete: Bool {
        points.count >= type.requiredPoints
    }
}
