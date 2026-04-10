import Foundation

/// iCloud 동기화되는 앱 설정 모델입니다.
struct AppSettings: Codable, Sendable {
    var isAppLockEnabled: Bool
    var lastSyncDate: Date

    init(isAppLockEnabled: Bool = false, lastSyncDate: Date = .distantPast) {
        self.isAppLockEnabled = isAppLockEnabled
        self.lastSyncDate = lastSyncDate
    }
}
