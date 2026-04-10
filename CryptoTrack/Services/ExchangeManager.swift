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

    init() {
        loadRegisteredExchanges()
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

    private func loadRegisteredExchanges() {
        guard let names = UserDefaults.standard.stringArray(forKey: userDefaultsKey) else { return }
        let exchanges = names.compactMap { Exchange(rawValue: $0) }
        for exchange in exchanges {
            services[exchange] = createService(for: exchange)
        }
        registeredExchanges = exchanges
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
