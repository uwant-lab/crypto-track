import SwiftUI
import Observation

@Observable
@MainActor
final class AppLockManager {
    static let shared = AppLockManager()

    var isLocked: Bool = false
    var isAppLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAppLockEnabled, forKey: Self.appLockEnabledKey)
            isLocked = isAppLockEnabled
            // iCloud에 설정 동기화
            let settings = AppSettings(isAppLockEnabled: isAppLockEnabled, lastSyncDate: Date())
            CloudSyncService.shared.syncSettings(settings)
        }
    }

    private static let appLockEnabledKey = "appLockEnabled"
    private let authService = BiometricAuthService.shared

    private init() {
        self.isAppLockEnabled = UserDefaults.standard.bool(forKey: Self.appLockEnabledKey)
        if isAppLockEnabled {
            self.isLocked = true
        }
        syncFromCloud()
    }

    // MARK: - Cloud Sync

    /// iCloud에서 앱 잠금 설정을 가져와 로컬 상태를 업데이트합니다.
    func syncFromCloud() {
        guard let settings = CloudSyncService.shared.loadSettings() else { return }
        let cloudValue = settings.isAppLockEnabled
        guard cloudValue != isAppLockEnabled else { return }
        isAppLockEnabled = cloudValue
        UserDefaults.standard.set(isAppLockEnabled, forKey: Self.appLockEnabledKey)
    }

    func unlock() async {
        guard isAppLockEnabled else {
            isLocked = false
            return
        }
        do {
            let success = try await authService.authenticate()
            if success {
                isLocked = false
                // 잠금 해제 후 등록된 거래소의 API 키를 일괄 preload한다.
                // 이후 대시보드 refresh는 캐시에서 바로 응답돼 키체인 프롬프트가
                // 발생하지 않는다.
                ExchangeManager.shared.preloadKeychainCache()
            }
        } catch {
            // Authentication failed or was cancelled — remain locked
        }
    }

    func lock() {
        guard isAppLockEnabled else { return }
        isLocked = true
        // 앱이 잠기면 메모리 캐시도 비워 민감 정보가 RAM에 머무르지 않게 한다.
        // Keychain 자체는 그대로 유지된다.
        KeychainService.shared.invalidateCache()
    }

    func toggleAppLock() {
        isAppLockEnabled.toggle()
    }
}
