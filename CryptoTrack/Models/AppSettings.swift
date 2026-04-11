import Foundation

/// iCloud 동기화되는 앱 설정 모델입니다.
struct AppSettings: Codable, Sendable {
    var isAppLockEnabled: Bool
    var lastSyncDate: Date
    var priceColorMode: PriceColorMode

    init(
        isAppLockEnabled: Bool = false,
        lastSyncDate: Date = .distantPast,
        priceColorMode: PriceColorMode = .korean
    ) {
        self.isAppLockEnabled = isAppLockEnabled
        self.lastSyncDate = lastSyncDate
        self.priceColorMode = priceColorMode
    }

    enum CodingKeys: String, CodingKey {
        case isAppLockEnabled
        case lastSyncDate
        case priceColorMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isAppLockEnabled = try container.decode(Bool.self, forKey: .isAppLockEnabled)
        self.lastSyncDate = try container.decode(Date.self, forKey: .lastSyncDate)
        // priceColorMode는 기존 iCloud payload엔 없을 수 있으므로 기본값 fallback
        self.priceColorMode = try container.decodeIfPresent(PriceColorMode.self, forKey: .priceColorMode) ?? .korean
    }
}
