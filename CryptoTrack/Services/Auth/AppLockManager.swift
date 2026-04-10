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
            if isAppLockEnabled {
                isLocked = true
            } else {
                isLocked = false
            }
        }
    }

    private static let appLockEnabledKey = "appLockEnabled"
    private let authService = BiometricAuthService.shared

    private init() {
        self.isAppLockEnabled = UserDefaults.standard.bool(forKey: Self.appLockEnabledKey)
        if isAppLockEnabled {
            self.isLocked = true
        }
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
