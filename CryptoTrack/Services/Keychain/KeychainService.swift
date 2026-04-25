import Foundation
import Security

enum KeychainError: LocalizedError {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "이미 저장된 항목이 존재합니다."
        case .itemNotFound:
            return "저장된 항목을 찾을 수 없습니다."
        case .unexpectedStatus(let status):
            return "Keychain 오류: \(status)"
        case .invalidData:
            return "데이터를 변환할 수 없습니다."
        }
    }
}

/// Apple Keychain을 사용하여 API Key를 안전하게 저장·조회·삭제하는 서비스.
/// UserDefaults나 파일 시스템에 민감 정보를 저장하지 않습니다.
///
/// **In-memory 캐시:**
/// macOS ad-hoc 빌드에서는 Keychain 읽기가 "login 키체인 ACL 프롬프트"를 매번
/// 띄울 수 있습니다(앱 바이너리 해시가 서명 ID에 귀속되지 않기 때문). 이 캐시는
/// 세션당 각 아이템을 한 번만 실제로 읽도록 해서 프롬프트를 최소화합니다.
/// - 첫 `read`: Keychain 접근 (프롬프트 발생 가능) → 캐시에 저장
/// - 이후 `read`: 캐시 hit → 조용
/// - `save`/`update`: Keychain에 쓴 뒤 캐시도 갱신 (write-through)
/// - `delete`/`deleteAll`: Keychain에서 지우고 캐시에서도 제거
/// - `invalidateCache()`: 캐시만 비움 (Keychain 그대로). `AppLockManager.lock()`
///   시 호출해 앱 잠금 동안 민감 정보가 메모리에 머무르지 않게 한다.
/// - `preloadCache(account:keys:)`: 시작 시점(또는 잠금 해제 직후)에 모든 키를
///   한 번에 읽어 프롬프트를 대시보드 사용 중이 아닌 시작 시점에 모아준다.
///
/// 스레드 안전: 캐시 접근은 `NSLock`로 보호합니다. 호출자는 main actor가 아닐
/// 수 있어(`Sendable`) 명시 동기화가 필요합니다.
final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()

    private let serviceIdentifier = "com.cryptotrack.apikeys"

    // MARK: - Cache State

    private let cacheLock = NSLock()
    private var cache: [String: String] = [:]

    private init() {}

    private func cacheKey(_ key: String, _ account: String) -> String {
        "\(account).\(key)"
    }

    // MARK: - Save

    func save(key: String, value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: "\(account).\(key)",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            setCache(key: key, account: account, value: value)
        case errSecDuplicateItem:
            try update(key: key, value: value, account: account)
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Read

    func read(key: String, account: String) throws -> String {
        if let cached = getCache(key: key, account: account) {
            return cached
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: "\(account).\(key)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        setCache(key: key, account: account, value: value)
        return value
    }

    // MARK: - Update

    private func update(key: String, value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: "\(account).\(key)"
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        setCache(key: key, account: account, value: value)
    }

    // MARK: - Delete

    func delete(key: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: "\(account).\(key)"
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        removeCache(key: key, account: account)
    }

    // MARK: - Delete All (for a specific account/exchange)

    func deleteAll(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        removeAllCache(account: account)
    }

    // MARK: - Cache Control (public)

    /// 지정한 account의 키들을 한꺼번에 읽어 캐시에 적재합니다.
    /// 개별 실패(`errSecItemNotFound` 등)는 무시합니다 — best-effort.
    /// 앱 시작 또는 `AppLockManager.unlockWithPIN()` / `unlockWithBiometrics()` 성공 시
    /// 호출해 키체인 프롬프트를 시작 시점으로 모아주세요.
    func preloadCache(account: String, keys: [String]) {
        for key in keys {
            _ = try? read(key: key, account: account)
        }
    }

    /// 메모리 캐시를 모두 비웁니다. Keychain 저장소는 건드리지 않습니다.
    /// `AppLockManager.lock()`에서 호출해 앱 잠금 동안 메모리에 키를 남기지
    /// 않도록 합니다.
    func invalidateCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    // MARK: - Cache Helpers (private)

    private func getCache(key: String, account: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[cacheKey(key, account)]
    }

    private func setCache(key: String, account: String, value: String) {
        cacheLock.lock()
        cache[cacheKey(key, account)] = value
        cacheLock.unlock()
    }

    private func removeCache(key: String, account: String) {
        cacheLock.lock()
        cache.removeValue(forKey: cacheKey(key, account))
        cacheLock.unlock()
    }

    private func removeAllCache(account: String) {
        cacheLock.lock()
        let prefix = "\(account)."
        let keysToRemove = cache.keys.filter { $0.hasPrefix(prefix) }
        for k in keysToRemove {
            cache.removeValue(forKey: k)
        }
        cacheLock.unlock()
    }
}
