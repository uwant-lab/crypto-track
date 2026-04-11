import Foundation
import Observation

/// 등록된 거래소들을 관리하고 데이터를 집계하는 중앙 서비스.
/// 거래소 목록은 UserDefaults에, API 키는 Keychain에만 저장합니다.
@Observable
@MainActor
final class ExchangeManager {

    // MARK: - Singleton

    static let shared = ExchangeManager()

    // MARK: - Observable State

    /// 사용자가 API 키를 등록한 거래소 목록
    private(set) var registeredExchanges: [Exchange] = []

    /// 활성화된 거래소 서비스 인스턴스
    private(set) var services: [Exchange: any ExchangeService] = [:]

    // MARK: - Private Properties

    private let userDefaultsKey = "registeredExchanges"

    // MARK: - Init

    /// - Parameter hydrateFromKeychain: `true`이면 Keychain에 API 키가 존재하지만
    ///   UserDefaults `registeredExchanges`에는 빠져 있는 거래소를 자동으로 복구한다.
    ///   테스트는 `false`로 호출해 머신 Keychain 상태가 테스트에 새어 들어오는 것을 막는다.
    init(hydrateFromKeychain: Bool = true) {
        loadRegisteredExchanges(hydrateFromKeychain: hydrateFromKeychain)
        syncFromCloud()
    }

    // MARK: - Registration

    /// 거래소를 등록하고 서비스 인스턴스를 생성합니다.
    func register(exchange: Exchange) {
        guard !isRegistered(exchange) else { return }
        services[exchange] = createService(for: exchange)
        registeredExchanges.append(exchange)
        saveRegisteredExchanges()
    }

    /// 거래소 등록을 해제하고 Keychain에서 API 키를 삭제합니다.
    func unregister(exchange: Exchange) {
        services.removeValue(forKey: exchange)
        registeredExchanges.removeAll { $0 == exchange }
        saveRegisteredExchanges()

        // Keychain에서 해당 거래소의 API 키 삭제
        try? KeychainService.shared.deleteAll(account: exchange.rawValue)
    }

    /// 해당 거래소가 등록되어 있는지 확인합니다.
    func isRegistered(_ exchange: Exchange) -> Bool {
        registeredExchanges.contains(exchange)
    }

    // MARK: - Aggregated Fetch

    /// 등록된 모든 거래소에서 자산을 병렬로 조회합니다.
    /// 개별 거래소 실패는 무시하고 성공한 결과만 반환합니다.
    func fetchAllAssets() async throws -> [Asset] {
        guard !registeredExchanges.isEmpty else { return [] }

        return await withTaskGroup(of: [Asset].self) { group in
            for exchange in registeredExchanges {
                guard let service = services[exchange] else { continue }
                group.addTask {
                    do {
                        return try await service.fetchAssets()
                    } catch {
                        return []
                    }
                }
            }

            var allAssets: [Asset] = []
            for await assets in group {
                allAssets.append(contentsOf: assets)
            }
            return allAssets
        }
    }

    /// 등록된 모든 거래소에서 시세를 병렬로 조회합니다.
    /// 개별 거래소 실패는 무시하고 성공한 결과만 반환합니다.
    func fetchAllTickers(symbols: [String]) async throws -> [Ticker] {
        guard !registeredExchanges.isEmpty else { return [] }

        return await withTaskGroup(of: [Ticker].self) { group in
            for exchange in registeredExchanges {
                guard let service = services[exchange] else { continue }
                group.addTask {
                    do {
                        return try await service.fetchTickers(symbols: symbols)
                    } catch {
                        return []
                    }
                }
            }

            var allTickers: [Ticker] = []
            for await tickers in group {
                allTickers.append(contentsOf: tickers)
            }
            return allTickers
        }
    }

    // MARK: - Per-Exchange Fetch (with status tracking)

    /// 등록된 모든 거래소에서 자산을 병렬 조회하되, 거래소별 성공/실패를 그대로 반환합니다.
    /// `fetchAllAssets()`와 달리 일부 실패를 사용자에게 보여주고 싶을 때 사용합니다.
    func fetchAssetsPerExchange() async -> [(Exchange, Result<[Asset], Error>)] {
        guard !registeredExchanges.isEmpty else { return [] }

        return await withTaskGroup(of: (Exchange, Result<[Asset], Error>).self) { group in
            for exchange in registeredExchanges {
                guard let service = services[exchange] else { continue }
                group.addTask {
                    do {
                        let list = try await service.fetchAssets()
                        return (exchange, .success(list))
                    } catch {
                        return (exchange, .failure(error))
                    }
                }
            }

            var results: [(Exchange, Result<[Asset], Error>)] = []
            for await item in group {
                results.append(item)
            }
            return results
        }
    }

    /// Per-exchange ticker fetch scoped to each exchange's own holdings. Each
    /// exchange task only receives the symbols it was asked to fetch — previously
    /// the callsite passed the union of all symbols, which caused single-batch
    /// APIs (Binance/Upbit/Bithumb) to fail entire requests whenever any symbol
    /// wasn't listed on that exchange.
    func fetchTickersPerExchange(
        symbolsByExchange: [Exchange: [String]]
    ) async -> [(Exchange, Result<[Ticker], Error>)] {
        guard !registeredExchanges.isEmpty else { return [] }

        return await withTaskGroup(of: (Exchange, Result<[Ticker], Error>).self) { group in
            for exchange in registeredExchanges {
                guard let service = services[exchange] else { continue }
                let symbols = symbolsByExchange[exchange] ?? []
                group.addTask {
                    guard !symbols.isEmpty else {
                        return (exchange, .success([]))
                    }
                    do {
                        let list = try await service.fetchTickers(symbols: symbols)
                        return (exchange, .success(list))
                    } catch {
                        return (exchange, .failure(error))
                    }
                }
            }

            var results: [(Exchange, Result<[Ticker], Error>)] = []
            for await item in group {
                results.append(item)
            }
            return results
        }
    }

    /// 특정 거래소의 API 연결을 검증합니다.
    func validateConnection(for exchange: Exchange) async throws -> Bool {
        guard let service = services[exchange] else { return false }
        return try await service.validateConnection()
    }

    // MARK: - Cloud Sync

    /// iCloud에서 거래소 목록을 가져와 로컬 상태를 업데이트합니다.
    func syncFromCloud() {
        guard let cloudExchanges = CloudSyncService.shared.loadRegisteredExchanges() else { return }
        // 클라우드 목록을 기준으로 로컬 상태를 병합합니다 (last-write-wins).
        for exchange in cloudExchanges where !isRegistered(exchange) {
            services[exchange] = createService(for: exchange)
            registeredExchanges.append(exchange)
        }
        saveRegisteredExchanges()
    }

    // MARK: - Persistence

    private func saveRegisteredExchanges() {
        let names = registeredExchanges.map { $0.rawValue }
        UserDefaults.standard.set(names, forKey: userDefaultsKey)
        CloudSyncService.shared.syncRegisteredExchanges(registeredExchanges)
    }

    private func loadRegisteredExchanges(hydrateFromKeychain: Bool) {
        let userDefaultsNames = UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
        let fromUserDefaults = userDefaultsNames.compactMap { Exchange(rawValue: $0) }

        // Self-heal: Keychain 스캔 fallback.
        // 과거(6bdf92a fix 이전)에 저장되어 Keychain에만 존재하고 UserDefaults
        // `registeredExchanges`에는 기록되지 않은 거래소를 복구한다.
        let fromKeychain = hydrateFromKeychain
            ? Exchange.allCases.filter { Self.hasAPIKeysInKeychain(for: $0) }
            : []

        // 두 소스를 병합하고 Exchange.allCases 순서로 정렬해 안정적인 UI 순서를 유지한다.
        let merged: [Exchange] = Exchange.allCases.filter {
            fromUserDefaults.contains($0) || fromKeychain.contains($0)
        }

        for exchange in merged {
            services[exchange] = createService(for: exchange)
        }
        registeredExchanges = merged

        // Keychain으로부터 복구된 항목이 있으면 UserDefaults에 영속화한다.
        if Set(merged) != Set(fromUserDefaults) {
            saveRegisteredExchanges()
        }

        // 모든 등록된 거래소의 API 키를 캐시에 일괄 로드한다.
        // 이후 대시보드 refresh 시점에 키체인 프롬프트가 흩어지지 않고,
        // 앱 시작 시점에 한 번에 처리된다.
        if hydrateFromKeychain {
            preloadKeychainCache()
        }
    }

    /// 등록된 모든 거래소의 Keychain 아이템을 한 번에 읽어 캐시에 적재합니다.
    /// `AppLockManager.unlock()` 성공 이후에도 호출해 잠금 해제 후 첫 refresh가
    /// 프롬프트 없이 돌아가도록 합니다.
    func preloadKeychainCache() {
        for exchange in registeredExchanges {
            KeychainService.shared.preloadCache(
                account: exchange.rawValue.lowercased(),
                keys: Self.keychainKeyNames(for: exchange)
            )
        }
    }

    /// Keychain에 해당 거래소의 API 키가 저장되어 있는지 확인합니다.
    /// 거래소별 primary key 이름이 다르므로 switch로 분기합니다.
    private static func hasAPIKeysInKeychain(for exchange: Exchange) -> Bool {
        let account = exchange.rawValue.lowercased()
        let primaryKey: String = keychainKeyNames(for: exchange).first ?? "accessKey"
        return (try? KeychainService.shared.read(key: primaryKey, account: account)) != nil
    }

    /// 거래소별로 Keychain에 저장되는 key 이름 목록.
    /// 첫 번째가 "primary" (존재 여부 판정용), 나머지는 함께 preload된다.
    static func keychainKeyNames(for exchange: Exchange) -> [String] {
        switch exchange {
        case .korbit:
            // clientId/clientSecret가 primary. 토큰 캐시도 함께 preload해
            // 재발급 로직이 프롬프트 없이 진행되도록 한다.
            return ["clientId", "clientSecret", "accessToken", "refreshToken", "tokenExpiry"]
        case .okx:
            return ["apiKey", "secretKey", "passphrase"]
        default:
            return ["accessKey", "secretKey"]
        }
    }

    // MARK: - Factory

    private func createService(for exchange: Exchange) -> any ExchangeService {
        switch exchange {
        case .upbit:
            return UpbitService()
        case .binance:
            return BinanceService()
        case .bithumb:
            return BithumbService()
        case .bybit:
            return BybitService()
        case .coinone:
            return CoinoneService()
        case .korbit:
            return KorbitService()
        case .okx:
            return OKXService()
        }
    }
}
