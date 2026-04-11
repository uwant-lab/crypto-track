import Foundation
import Observation
import Security

/// iCloud Key-Value Store를 사용하는 중앙 동기화 코디네이터입니다.
/// NSUbiquitousKeyValueStore는 앱 설정과 거래소 목록(1MB 이하)에 적합합니다.
///
/// - Note: API 키는 보안 정책상 iCloud 동기화에서 제외됩니다.
///   KeychainService가 kSecAttrAccessibleWhenUnlockedThisDeviceOnly를 사용하므로
///   API 키는 기기 간 동기화되지 않습니다. 이는 의도된 보안 설계입니다.
@Observable
@MainActor
final class CloudSyncService {

    // MARK: - Singleton

    static let shared = CloudSyncService()

    // MARK: - Observable State

    /// iCloud 동기화 가능 여부
    private(set) var isICloudAvailable: Bool = false

    /// 마지막 동기화 시각
    private(set) var lastSyncDate: Date?

    // MARK: - Keys

    private enum Keys {
        static let registeredExchanges = "sync.registeredExchanges"
        static let appSettings = "sync.appSettings"
    }

    // MARK: - Private Properties

    /// iCloud entitlement가 없는 빌드에서는 nil로 유지되어 NSUbiquitousKeyValueStore 초기화 경고를 방지합니다.
    private var kvStore: NSUbiquitousKeyValueStore?

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Init

    private init() {
        isICloudAvailable = checkICloudAvailability()
        if isICloudAvailable {
            kvStore = NSUbiquitousKeyValueStore.default
        }
    }

    // MARK: - Lifecycle

    /// 원격 변경 알림 수신을 시작합니다.
    func startObserving() {
        guard let kvStore else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )
        kvStore.synchronize()
        isICloudAvailable = checkICloudAvailability()
    }

    /// 원격 변경 알림 수신을 중지합니다.
    func stopObserving() {
        guard let kvStore else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )
    }

    // MARK: - Registered Exchanges Sync

    /// 등록된 거래소 목록을 iCloud KV Store에 동기화합니다.
    func syncRegisteredExchanges(_ exchanges: [Exchange]) {
        guard let kvStore, isICloudAvailable else { return }
        let names = exchanges.map { $0.rawValue }
        kvStore.set(names, forKey: Keys.registeredExchanges)
        kvStore.synchronize()
        lastSyncDate = Date()
    }

    /// iCloud KV Store에서 등록된 거래소 목록을 불러옵니다.
    func loadRegisteredExchanges() -> [Exchange]? {
        guard let kvStore, isICloudAvailable else { return nil }
        guard let names = kvStore.array(forKey: Keys.registeredExchanges) as? [String] else { return nil }
        let exchanges = names.compactMap { Exchange(rawValue: $0) }
        return exchanges.isEmpty ? nil : exchanges
    }

    // MARK: - App Settings Sync

    /// 앱 설정을 iCloud KV Store에 동기화합니다.
    func syncSettings(_ settings: AppSettings) {
        guard let kvStore, isICloudAvailable else { return }
        guard let data = try? Self.encoder.encode(settings) else { return }
        kvStore.set(data, forKey: Keys.appSettings)
        kvStore.synchronize()
        lastSyncDate = Date()
    }

    /// iCloud KV Store에서 앱 설정을 불러옵니다.
    func loadSettings() -> AppSettings? {
        guard let kvStore, isICloudAvailable else { return nil }
        guard let data = kvStore.data(forKey: Keys.appSettings) else { return nil }
        return try? Self.decoder.decode(AppSettings.self, from: data)
    }

    // MARK: - Manual Sync

    /// iCloud와 즉시 동기화를 수행합니다.
    func synchronizeNow() {
        guard let kvStore, isICloudAvailable else { return }
        kvStore.synchronize()
        lastSyncDate = Date()
    }

    // MARK: - Private

    /// iCloud entitlement와 로그인된 iCloud 계정이 모두 있을 때만 true.
    /// 사용자가 Mac에 iCloud 로그인만 되어 있으면 `ubiquityIdentityToken`은 non-nil이지만,
    /// 앱 바이너리에 `com.apple.developer.ubiquity-kvstore-identifier` entitlement가 서명되어 있지 않으면
    /// NSUbiquitousKeyValueStore 초기화 시 "BUG IN CLIENT OF KVS" 경고가 발생합니다.
    /// 따라서 entitlement 존재 여부를 먼저 확인합니다.
    private func checkICloudAvailability() -> Bool {
        guard Self.hasUbiquityKVSEntitlement() else { return false }
        return FileManager.default.ubiquityIdentityToken != nil
    }

    /// 앱 바이너리에 iCloud KVS entitlement가 서명되어 있는지 확인합니다.
    private static func hasUbiquityKVSEntitlement() -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = "com.apple.developer.ubiquity-kvstore-identifier" as CFString
        guard let value = SecTaskCopyValueForEntitlement(task, entitlement, nil) else {
            return false
        }
        if let string = value as? String, !string.isEmpty {
            return true
        }
        return false
        #else
        // iOS: SecTask* APIs are unavailable. Until the iCloud entitlement is
        // shipped with the iOS build (project.yml currently has
        // CODE_SIGN_ENTITLEMENTS commented out), treat iCloud KVS as
        // unavailable to avoid the "BUG IN CLIENT OF KVS" warning.
        return false
        #endif
    }

    @objc nonisolated private func handleExternalChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else { return }

        Task { @MainActor in
            self.lastSyncDate = Date()
            if changedKeys.contains(Keys.registeredExchanges) {
                ExchangeManager.shared.syncFromCloud()
            }
            if changedKeys.contains(Keys.appSettings) {
                AppLockManager.shared.syncFromCloud()
            }
        }
    }
}
