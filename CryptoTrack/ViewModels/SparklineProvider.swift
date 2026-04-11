import Foundation
import Observation

/// Dashboard row mini-sparkline data source.
///
/// Fetches 7-day daily klines per (exchange, symbol) pair from the registered
/// exchange services and caches the close-price arrays with a 1-hour TTL so the
/// dashboard's 30-second refresh loop doesn't thrash exchange rate limits.
///
/// Stale (but non-empty) cache entries are still returned — the next hydrate
/// cycle will replace them. Missing or failed fetches simply leave the cache
/// entry absent, and the view renders a dashed placeholder baseline.
@Observable
@MainActor
final class SparklineProvider {

    // MARK: - Nested types

    struct Key: Hashable, Sendable {
        let exchange: Exchange
        let symbol: String
    }

    private struct Entry {
        let prices: [Double]
        let fetchedAt: Date
    }

    // MARK: - Constants

    private static let ttl: TimeInterval = 3600 // 1 hour
    private static let klineLimit = 7
    private static let timeframe: ChartTimeframe = .day1

    // MARK: - State

    private var cache: [Key: Entry] = [:]

    // MARK: - Dependencies

    private let exchangeManager: ExchangeManager

    init(exchangeManager: ExchangeManager = .shared) {
        self.exchangeManager = exchangeManager
    }

    // MARK: - Public

    /// Cached 7-day close prices (chronological) for the given pair, or nil
    /// if no entry exists yet. Staleness is NOT surfaced — callers get
    /// whatever's available while the next hydrate cycle runs.
    func sparkline(exchange: Exchange, symbol: String) -> [Double]? {
        cache[Key(exchange: exchange, symbol: symbol)]?.prices
    }

    /// Ensures every pair in `pairs` has a fresh entry. Pairs whose cached
    /// entry is younger than `ttl` are skipped. The remainder are fetched
    /// concurrently; individual failures leave that entry untouched.
    ///
    /// Safe to call from a fire-and-forget Task — never throws, and writes
    /// to `cache` happen on the MainActor so SwiftUI observers update.
    func hydrate(pairs: Set<Key>) async {
        let now = Date()
        let stale = pairs.filter { isStale($0, now: now) }
        guard !stale.isEmpty else { return }

        // Resolve services while still on MainActor before fanning out.
        let fetches: [(Key, any ExchangeService)] = stale.compactMap { key in
            guard let service = exchangeManager.services[key.exchange] else {
                return nil
            }
            return (key, service)
        }
        guard !fetches.isEmpty else { return }

        let results = await withTaskGroup(of: (Key, [Double]).self) { group -> [(Key, [Double])] in
            for (key, service) in fetches {
                group.addTask {
                    do {
                        let klines = try await service.fetchKlines(
                            symbol: key.symbol,
                            timeframe: Self.timeframe,
                            limit: Self.klineLimit
                        )
                        return (key, klines.map(\.close))
                    } catch {
                        return (key, [])
                    }
                }
            }
            var collected: [(Key, [Double])] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        let fetchedAt = Date()
        for (key, prices) in results where !prices.isEmpty {
            cache[key] = Entry(prices: prices, fetchedAt: fetchedAt)
        }
    }

    // MARK: - Private

    private func isStale(_ key: Key, now: Date) -> Bool {
        guard let entry = cache[key] else { return true }
        return now.timeIntervalSince(entry.fetchedAt) > Self.ttl
    }
}
