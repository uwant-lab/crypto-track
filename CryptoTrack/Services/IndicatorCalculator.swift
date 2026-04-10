import Foundation

/// Pure calculation engine for technical indicators.
/// All methods are static and side-effect free.
enum IndicatorCalculator {

    // MARK: - Moving Average (MA / SMA)

    /// Simple Moving Average over `period` candles using close prices.
    static func calculateMA(klines: [Kline], period: Int) -> [IndicatorValue] {
        guard period > 0, klines.count >= period else { return [] }
        var result: [IndicatorValue] = []
        result.reserveCapacity(klines.count - period + 1)

        for i in (period - 1)..<klines.count {
            let slice = klines[(i - period + 1)...i]
            let sum = slice.reduce(0.0) { $0 + $1.close }
            let ma = sum / Double(period)
            result.append(IndicatorValue(timestamp: klines[i].timestamp, values: ["ma": ma]))
        }
        return result
    }

    // MARK: - Exponential Moving Average (EMA)

    /// Exponential Moving Average over `period` candles using close prices.
    static func calculateEMA(klines: [Kline], period: Int) -> [IndicatorValue] {
        guard period > 0, klines.count >= period else { return [] }
        let multiplier = 2.0 / Double(period + 1)

        // Seed with SMA of the first `period` candles
        let seedSlice = klines[0..<period]
        var ema = seedSlice.reduce(0.0) { $0 + $1.close } / Double(period)

        var result: [IndicatorValue] = []
        result.reserveCapacity(klines.count - period + 1)
        result.append(IndicatorValue(timestamp: klines[period - 1].timestamp, values: ["ema": ema]))

        for i in period..<klines.count {
            ema = (klines[i].close - ema) * multiplier + ema
            result.append(IndicatorValue(timestamp: klines[i].timestamp, values: ["ema": ema]))
        }
        return result
    }

    // MARK: - Bollinger Bands

    /// Bollinger Bands: middle = SMA(period), upper/lower = middle ± multiplier * stddev.
    static func calculateBollingerBands(
        klines: [Kline],
        period: Int,
        multiplier: Double
    ) -> [IndicatorValue] {
        guard period > 0, klines.count >= period else { return [] }
        var result: [IndicatorValue] = []
        result.reserveCapacity(klines.count - period + 1)

        for i in (period - 1)..<klines.count {
            let slice = klines[(i - period + 1)...i].map(\.close)
            let mean = slice.reduce(0.0, +) / Double(period)
            let variance = slice.reduce(0.0) { acc, x in
                let diff = x - mean
                return acc + diff * diff
            } / Double(period)
            let stddev = variance.squareRoot()
            result.append(IndicatorValue(
                timestamp: klines[i].timestamp,
                values: [
                    "upper":  mean + multiplier * stddev,
                    "middle": mean,
                    "lower":  mean - multiplier * stddev
                ]
            ))
        }
        return result
    }

    // MARK: - RSI

    /// Relative Strength Index (Wilder smoothing) using close prices. Output range: 0–100.
    static func calculateRSI(klines: [Kline], period: Int) -> [IndicatorValue] {
        guard period > 0, klines.count > period else { return [] }
        var result: [IndicatorValue] = []

        // Compute price changes
        var gains = [Double]()
        var losses = [Double]()
        gains.reserveCapacity(klines.count - 1)
        losses.reserveCapacity(klines.count - 1)

        for i in 1..<klines.count {
            let delta = klines[i].close - klines[i - 1].close
            gains.append(max(0, delta))
            losses.append(max(0, -delta))
        }

        // Initial average gain/loss (SMA seed)
        var avgGain = gains[0..<period].reduce(0.0, +) / Double(period)
        var avgLoss = losses[0..<period].reduce(0.0, +) / Double(period)

        let rsi0 = avgLoss == 0 ? 100.0 : 100.0 - 100.0 / (1.0 + avgGain / avgLoss)
        result.append(IndicatorValue(timestamp: klines[period].timestamp, values: ["rsi": rsi0]))

        // Wilder smoothing for remaining candles
        for i in period..<gains.count {
            avgGain = (avgGain * Double(period - 1) + gains[i]) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + losses[i]) / Double(period)
            let rsi = avgLoss == 0 ? 100.0 : 100.0 - 100.0 / (1.0 + avgGain / avgLoss)
            result.append(IndicatorValue(timestamp: klines[i + 1].timestamp, values: ["rsi": rsi]))
        }
        return result
    }

    // MARK: - MACD

    /// MACD line, signal line, and histogram.
    /// macd = EMA(fast) − EMA(slow), signal = EMA(macd, signal), histogram = macd − signal
    static func calculateMACD(
        klines: [Kline],
        fast: Int,
        slow: Int,
        signal: Int
    ) -> [IndicatorValue] {
        guard klines.count > slow + signal else { return [] }

        // Build aligned EMA arrays
        let fastEMAs = calculateEMA(klines: klines, period: fast)
        let slowEMAs = calculateEMA(klines: klines, period: slow)

        // Align by timestamp
        let slowTimestamps = Dictionary(uniqueKeysWithValues: slowEMAs.map { ($0.timestamp, $0.values["ema"]!) })
        var macdLine: [(Date, Double)] = []
        for fv in fastEMAs {
            guard let slowVal = slowTimestamps[fv.timestamp] else { continue }
            macdLine.append((fv.timestamp, fv.values["ema"]! - slowVal))
        }

        guard macdLine.count >= signal else { return [] }

        // Compute signal EMA on the macd line
        let signalMultiplier = 2.0 / Double(signal + 1)
        var sigEMA = macdLine[0..<signal].reduce(0.0) { $0 + $1.1 } / Double(signal)

        var result: [IndicatorValue] = []
        result.reserveCapacity(macdLine.count - signal + 1)

        let firstMACD = macdLine[signal - 1].1
        let hist0 = firstMACD - sigEMA
        result.append(IndicatorValue(
            timestamp: macdLine[signal - 1].0,
            values: ["macd": firstMACD, "signal": sigEMA, "histogram": hist0]
        ))

        for i in signal..<macdLine.count {
            let macdVal = macdLine[i].1
            sigEMA = (macdVal - sigEMA) * signalMultiplier + sigEMA
            let hist = macdVal - sigEMA
            result.append(IndicatorValue(
                timestamp: macdLine[i].0,
                values: ["macd": macdVal, "signal": sigEMA, "histogram": hist]
            ))
        }
        return result
    }

    // MARK: - Stochastic Oscillator

    /// Stochastic %K and %D.
    /// Raw %K = (close − lowest_low) / (highest_high − lowest_low) × 100
    /// Smoothed %K = SMA(raw %K, smoothK), %D = SMA(smoothed %K, smoothD)
    static func calculateStochastic(
        klines: [Kline],
        period: Int,
        smoothK: Int,
        smoothD: Int
    ) -> [IndicatorValue] {
        guard klines.count >= period + smoothK + smoothD - 2 else { return [] }

        // Raw %K
        var rawK: [(Date, Double)] = []
        for i in (period - 1)..<klines.count {
            let slice = klines[(i - period + 1)...i]
            let lowest  = slice.map(\.low).min()!
            let highest = slice.map(\.high).max()!
            let denom = highest - lowest
            let k = denom == 0 ? 50.0 : (klines[i].close - lowest) / denom * 100.0
            rawK.append((klines[i].timestamp, k))
        }

        // Smooth %K
        guard rawK.count >= smoothK else { return [] }
        var smoothedK: [(Date, Double)] = []
        for i in (smoothK - 1)..<rawK.count {
            let avg = rawK[(i - smoothK + 1)...i].reduce(0.0) { $0 + $1.1 } / Double(smoothK)
            smoothedK.append((rawK[i].0, avg))
        }

        // %D = SMA(smoothed %K, smoothD)
        guard smoothedK.count >= smoothD else { return [] }
        var result: [IndicatorValue] = []
        for i in (smoothD - 1)..<smoothedK.count {
            let dAvg = smoothedK[(i - smoothD + 1)...i].reduce(0.0) { $0 + $1.1 } / Double(smoothD)
            result.append(IndicatorValue(
                timestamp: smoothedK[i].0,
                values: ["k": smoothedK[i].1, "d": dAvg]
            ))
        }
        return result
    }

    // MARK: - On-Balance Volume (OBV)

    /// OBV accumulates volume: +volume when close > prev close, −volume when close < prev close.
    static func calculateOBV(klines: [Kline]) -> [IndicatorValue] {
        guard klines.count > 1 else { return [] }
        var obv = 0.0
        var result: [IndicatorValue] = []
        result.reserveCapacity(klines.count - 1)

        for i in 1..<klines.count {
            if klines[i].close > klines[i - 1].close {
                obv += klines[i].volume
            } else if klines[i].close < klines[i - 1].close {
                obv -= klines[i].volume
            }
            result.append(IndicatorValue(timestamp: klines[i].timestamp, values: ["obv": obv]))
        }
        return result
    }

    // MARK: - Dispatch

    /// Convenience: compute indicator values for a given config.
    static func calculate(config: IndicatorConfig, klines: [Kline]) -> [IndicatorValue] {
        switch config.type {
        case .ma:
            let period = Int(config.parameters["period"] ?? 20)
            return calculateMA(klines: klines, period: period)
        case .ema:
            let period = Int(config.parameters["period"] ?? 20)
            return calculateEMA(klines: klines, period: period)
        case .bollingerBands:
            let period     = Int(config.parameters["period"] ?? 20)
            let multiplier = config.parameters["multiplier"] ?? 2.0
            return calculateBollingerBands(klines: klines, period: period, multiplier: multiplier)
        case .rsi:
            let period = Int(config.parameters["period"] ?? 14)
            return calculateRSI(klines: klines, period: period)
        case .macd:
            let fast   = Int(config.parameters["fast"] ?? 12)
            let slow   = Int(config.parameters["slow"] ?? 26)
            let signal = Int(config.parameters["signal"] ?? 9)
            return calculateMACD(klines: klines, fast: fast, slow: slow, signal: signal)
        case .stochastic:
            let period  = Int(config.parameters["period"] ?? 14)
            let smoothK = Int(config.parameters["smoothK"] ?? 3)
            let smoothD = Int(config.parameters["smoothD"] ?? 3)
            return calculateStochastic(klines: klines, period: period, smoothK: smoothK, smoothD: smoothD)
        case .obv:
            return calculateOBV(klines: klines)
        }
    }
}
