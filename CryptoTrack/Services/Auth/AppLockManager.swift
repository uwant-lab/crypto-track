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
            }
        } catch {
            // Authentication failed or was cancelled — remain locked
        }
    }

    func lock() {
        guard isAppLockEnabled else { return }
        isLocked = true
    }

    func toggleAppLock() {
        isAppLockEnabled.toggle()
    }
}
