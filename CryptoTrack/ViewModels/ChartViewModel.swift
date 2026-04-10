import Foundation
import Observation

/// 캔들스틱 차트 화면의 상태와 비즈니스 로직을 관리합니다.
@Observable
@MainActor
final class ChartViewModel {
    // MARK: - State

    var klines: [Kline] = []
    var selectedTimeframe: ChartTimeframe = .hour1
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var crosshairKline: Kline? = nil

    /// 현재 보이는 캔들 인덱스 범위 (줌/스크롤)
    var visibleRange: Range<Int> = 0..<60

    // MARK: - Indicator State

    /// Currently configured indicators (active on the chart)
    var activeIndicators: [IndicatorConfig] = []

    /// Computed indicator values keyed by IndicatorConfig.id
    var indicatorValues: [String: [IndicatorValue]] = [:]

    // MARK: - Properties

    let symbol: String
    let exchange: Exchange

    // MARK: - Init

    init(symbol: String, exchange: Exchange) {
        self.symbol = symbol
        self.exchange = exchange
    }

    // MARK: - Data Loading

    /// 캔들 데이터를 로드합니다. (현재는 샘플 데이터 사용)
    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 실제 API 연동은 별도 에이전트가 구현 예정 — 현재 샘플 데이터 사용
        try? await Task.sleep(for: .milliseconds(300))
        let sample = Self.generateSampleKlines(
            symbol: symbol,
            exchange: exchange,
            timeframe: selectedTimeframe,
            count: 100
        )
        klines = sample
        let end = min(sample.count, 60)
        visibleRange = max(0, sample.count - end)..<sample.count

        // Add default MA(20) on first load
        if activeIndicators.isEmpty {
            activeIndicators = [IndicatorConfig(type: .ma, parameters: ["period": 20])]
        }
        recalculateIndicators()
    }

    /// 타임프레임을 변경하고 데이터를 다시 로드합니다.
    func changeTimeframe(_ timeframe: ChartTimeframe) async {
        selectedTimeframe = timeframe
        crosshairKline = nil
        await loadData()
    }

    // MARK: - Indicators

    /// Add a new indicator of the given type with default parameters.
    func addIndicator(_ type: IndicatorType) {
        guard !activeIndicators.contains(where: { $0.type == type }) else { return }
        let config = IndicatorConfig(type: type)
        activeIndicators.append(config)
        let computed = IndicatorCalculator.calculate(config: config, klines: klines)
        indicatorValues[config.id] = computed
    }

    /// Remove the indicator with the given id.
    func removeIndicator(id: String) {
        activeIndicators.removeAll { $0.id == id }
        indicatorValues.removeValue(forKey: id)
    }

    /// Toggle visibility of the indicator with the given id.
    func toggleIndicatorVisibility(id: String) {
        guard let idx = activeIndicators.firstIndex(where: { $0.id == id }) else { return }
        activeIndicators[idx].isVisible.toggle()
    }

    /// Recompute all active indicator values from the full klines array.
    func recalculateIndicators() {
        var newValues = [String: [IndicatorValue]]()
        for config in activeIndicators {
            newValues[config.id] = IndicatorCalculator.calculate(config: config, klines: klines)
        }
        indicatorValues = newValues
    }

    // MARK: - Zoom / Scroll

    /// 핀치 제스처로 줌 조정 (scale > 1: 확대, scale < 1: 축소)
    func zoom(scale: CGFloat) {
        guard !klines.isEmpty else { return }
        let currentCount = visibleRange.count
        let newCount = Int((Double(currentCount) / Double(scale)).rounded())
        let clampedCount = max(5, min(klines.count, newCount))
        let center = (visibleRange.lowerBound + visibleRange.upperBound) / 2
        let half = clampedCount / 2
        let lower = max(0, center - half)
        let upper = min(klines.count, lower + clampedCount)
        visibleRange = lower..<upper
    }

    /// 드래그 제스처로 수평 스크롤 조정
    func scroll(offset: CGFloat, candleWidth: CGFloat) {
        guard candleWidth > 0, !klines.isEmpty else { return }
        let candlesDelta = Int((offset / candleWidth).rounded())
        guard candlesDelta != 0 else { return }
        let count = visibleRange.count
        let newLower = (visibleRange.lowerBound - candlesDelta)
            .clamped(to: 0...(klines.count - count))
        visibleRange = newLower..<(newLower + count)
    }

    // MARK: - Visible Klines

    var visibleKlines: [Kline] {
        guard !klines.isEmpty else { return [] }
        let lower = visibleRange.lowerBound.clamped(to: 0...(klines.count - 1))
        let upper = visibleRange.upperBound.clamped(to: lower...klines.count)
        return Array(klines[lower..<upper])
    }

    // MARK: - Sample Data

    /// 프리뷰 및 초기 로딩용 샘플 캔들 데이터를 생성합니다.
    static func generateSampleKlines(
        symbol: String,
        exchange: Exchange,
        timeframe: ChartTimeframe,
        count: Int
    ) -> [Kline] {
        var result: [Kline] = []
        var price: Double = 42_000
        let intervalSeconds: TimeInterval = timeframeInterval(timeframe)
        let now = Date()
        var seed: UInt64 = 12345

        for i in 0..<count {
            // 단순 의사난수 생성 (재현 가능한 샘플)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r1 = Double(seed >> 33) / Double(UInt32.max)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r2 = Double(seed >> 33) / Double(UInt32.max)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r3 = Double(seed >> 33) / Double(UInt32.max)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r4 = Double(seed >> 33) / Double(UInt32.max)

            let bodySize = price * 0.015 * (r1 * 2 - 1)
            let open = price
            let close = price + bodySize
            let wickTop = max(open, close) + price * 0.008 * r2
            let wickBottom = min(open, close) - price * 0.008 * r3
            let volume = 100 + r4 * 900

            let timestamp = now.addingTimeInterval(-Double(count - i) * intervalSeconds)

            result.append(Kline(
                id: "\(symbol)-\(exchange.rawValue)-\(timeframe.rawValue)-\(i)",
                timestamp: timestamp,
                open: open,
                high: wickTop,
                low: wickBottom,
                close: close,
                volume: volume,
                timeframe: timeframe,
                exchange: exchange,
                symbol: symbol
            ))

            price = close
        }
        return result
    }

    private static func timeframeInterval(_ timeframe: ChartTimeframe) -> TimeInterval {
        switch timeframe {
        case .minute1:  return 60
        case .minute5:  return 300
        case .minute15: return 900
        case .hour1:    return 3_600
        case .hour4:    return 14_400
        case .day1:     return 86_400
        case .week1:    return 604_800
        case .month1:   return 2_592_000
        }
    }

    // MARK: - Preview

    static var preview: ChartViewModel {
        let vm = ChartViewModel(symbol: "BTC", exchange: .binance)
        let sample = generateSampleKlines(symbol: "BTC", exchange: .binance, timeframe: .hour1, count: 100)
        vm.klines = sample
        vm.selectedTimeframe = .hour1
        let end = min(sample.count, 60)
        vm.visibleRange = max(0, sample.count - end)..<sample.count
        return vm
    }
}

// MARK: - Comparable clamped helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
