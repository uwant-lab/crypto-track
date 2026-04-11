import Foundation
import Observation

/// Computes and caches average buy prices for exchanges whose account APIs
/// don't expose cost basis directly (Binance, Bybit, OKX).
///
/// The raw material is `fetchOrders` trade history across a 2-year window.
/// For each `(exchange, symbol)` pair we take every `.buy` order in the
/// window and compute a simple weighted average:
///
///     avgBuyPrice = Σ(buy.totalValue) / Σ(buy.amount)
///
/// This mirrors what Upbit/Bithumb return directly — a per-unit cost for
/// the holder's entire buy history. It ignores sells, which is correct for
/// the "average cost" interpretation most dashboards use; tracking the
/// exact remaining-balance cost basis would require FIFO lot matching and
/// persisted sell records, which is a heavier refactor we can do later.
///
/// Results persist in `UserDefaults` as JSON so they survive app launches.
/// Entries have a 24-hour TTL — historical trades rarely change but the
/// occasional new fill should get picked up once a day.
@Observable
@MainActor
final class ForeignCostBasisProvider {

    // MARK: - Types

    struct Pair: Hashable, Sendable {
        let exchange: Exchange
        let symbol: String
    }

    private struct Entry: Codable, Sendable {
        let averageBuyPrice: Double
        let computedAt: Date
    }

    // MARK: - Constants

    private static let userDefaultsKey = "foreignCostBasisCache.v1"
    private static let ttl: TimeInterval = 24 * 3600       // 24h
    private static let windowYears: Int = 2
    /// Upper bound on fetch loop iterations per exchange. Binance's
    /// page-as-symbol-index semantics means this also caps how many symbols
    /// we walk; 500 is well beyond anyone's realistic holdings count.
    private static let maxPagesPerExchange = 500

    // MARK: - Observable state

    /// True while an async `hydrate` pass is running. UI uses this to
    /// disable the trigger button and show a progress spinner.
    private(set) var isComputing: Bool = false

    /// Human-readable label for the current hydrate step (e.g. `"Binance"`).
    /// `nil` when idle.
    private(set) var progressLabel: String?

    // MARK: - Private state

    private var cache: [String: Entry] = [:]

    private let exchangeManager: ExchangeManager
    private let defaults: UserDefaults

    init(
        exchangeManager: ExchangeManager = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.exchangeManager = exchangeManager
        self.defaults = defaults
        loadFromDisk()
    }

    // MARK: - Public

    /// Cached average buy price for the pair, or nil if we haven't computed
    /// one yet. Stale entries are still returned — the next hydrate cycle
    /// will replace them.
    func averageBuyPrice(exchange: Exchange, symbol: String) -> Double? {
        cache[Self.key(exchange: exchange, symbol: symbol)]?.averageBuyPrice
    }

    /// Walks `pairs` and computes a fresh cost basis for every one whose
    /// cache entry is missing or older than `ttl`. Runs exchanges
    /// sequentially (one exchange at a time) to avoid rate-limit pressure,
    /// but fetches pages within an exchange in order because the trade APIs
    /// require it. Swallows individual failures so a bad exchange doesn't
    /// abort the whole pass.
    func hydrate(pairs: [Pair]) async {
        guard !isComputing else { return }
        isComputing = true
        defer {
            isComputing = false
            progressLabel = nil
        }

        let now = Date()
        let stale = pairs.filter { isStale($0, now: now) }
        guard !stale.isEmpty else { return }

        let byExchange = Dictionary(grouping: stale, by: \.exchange)

        let to = Date()
        let from = Calendar.current.date(byAdding: .year, value: -Self.windowYears, to: to) ?? to

        for (exchange, pairsInExchange) in byExchange {
            guard let service = exchangeManager.services[exchange] else { continue }
            progressLabel = exchange.rawValue

            let targets = Set(pairsInExchange.map(\.symbol))
            let orders = await collectOrders(service: service, from: from, to: to)

            // Group buy-side orders by symbol and compute weighted average.
            let buys = orders.filter { $0.side == .buy && targets.contains($0.symbol) }
            let bySymbol = Dictionary(grouping: buys, by: \.symbol)
            let computedAt = Date()
            for (symbol, list) in bySymbol {
                let totalAmount = list.reduce(0.0) { $0 + $1.amount }
                let totalCost = list.reduce(0.0) { $0 + $1.totalValue }
                guard totalAmount > 0 else { continue }
                let avg = totalCost / totalAmount
                let key = Self.key(exchange: exchange, symbol: symbol)
                cache[key] = Entry(averageBuyPrice: avg, computedAt: computedAt)
            }
        }

        saveToDisk()
    }

    // MARK: - Private

    /// Pulls all orders for the given exchange across the date window.
    /// Pagination follows whatever semantics each service uses (Binance
    /// advances per symbol, Upbit per page of trades, etc). Stops on error.
    private func collectOrders(
        service: any ExchangeService,
        from: Date,
        to: Date
    ) async -> [Order] {
        var collected: [Order] = []
        var page = 0
        while page < Self.maxPagesPerExchange {
            do {
                let result = try await service.fetchOrders(from: from, to: to, page: page)
                collected.append(contentsOf: result.items)
                if !result.hasMore { break }
                page += 1
            } catch {
                break
            }
        }
        return collected
    }

    private func isStale(_ pair: Pair, now: Date) -> Bool {
        let key = Self.key(exchange: pair.exchange, symbol: pair.symbol)
        guard let entry = cache[key] else { return true }
        return now.timeIntervalSince(entry.computedAt) > Self.ttl
    }

    private static func key(exchange: Exchange, symbol: String) -> String {
        "\(exchange.rawValue.lowercased())-\(symbol.uppercased())"
    }

    // MARK: - Persistence (UserDefaults)

    private func loadFromDisk() {
        guard let data = defaults.data(forKey: Self.userDefaultsKey) else { return }
        guard let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        cache = decoded
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }
}
