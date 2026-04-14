import SwiftUI
import Observation

@Observable
@MainActor
final class AppLockManager {
    static let shared = AppLockManager()

    var isLocked: Bool = false
    private(set) var isPINSet: Bool = false

    var isBiometricEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricEnabled, forKey: Self.biometricEnabledKey)
            let settings = AppSettings(isBiometricEnabled: isBiometricEnabled, lastSyncDate: Date())
            CloudSyncService.shared.syncSettings(settings)
        }
    }

    private static let biometricEnabledKey = "biometricEnabled"
    private let authService = BiometricAuthService.shared
    private let pinService = PINService.shared

    private init() {
        self.isBiometricEnabled = UserDefaults.standard.bool(forKey: Self.biometricEnabledKey)
        self.isPINSet = pinService.isPINSet
        if isPINSet {
            self.isLocked = true
        }
        syncFromCloud()
    }

    // MARK: - PIN State

    /// PINService의 상태를 읽어 isPINSet을 갱신합니다.
    /// PIN 설정/변경/해제 후 호출해야 SwiftUI가 변경을 감지합니다.
    func refreshPINState() {
        isPINSet = pinService.isPINSet
    }

    // MARK: - Cloud Sync

    func syncFromCloud() {
        guard let settings = CloudSyncService.shared.loadSettings() else { return }
        let cloudValue = settings.isBiometricEnabled
        guard cloudValue != isBiometricEnabled else { return }
        isBiometricEnabled = cloudValue
        UserDefaults.standard.set(isBiometricEnabled, forKey: Self.biometricEnabledKey)
    }

    // MARK: - Unlock

    /// PIN으로 잠금 해제를 시도합니다. 성공하면 true를 반환합니다.
    func unlockWithPIN(_ pin: String) -> Bool {
        guard pinService.verifyPIN(pin) else { return false }
        performUnlock()
        return true
    }

    /// 생체인증으로 잠금 해제를 시도합니다. 성공하면 true를 반환합니다.
    func unlockWithBiometrics() async -> Bool {
        guard isBiometricEnabled, authService.canUseBiometrics() else { return false }
        do {
            let success = try await authService.authenticate()
            if success {
                performUnlock()
                return true
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Lock

    func lock() {
        guard isPINSet else { return }
        isLocked = true
        KeychainService.shared.invalidateCache()
    }

    // MARK: - Private

    private func performUnlock() {
        isLocked = false
        ExchangeManager.shared.preloadKeychainCache()
    }
}
