import Foundation

/// iCloud 동기화되는 앱 설정 모델입니다.
struct AppSettings: Codable, Sendable {
    var isBiometricEnabled: Bool
    var lastSyncDate: Date
    var priceColorMode: PriceColorMode

    init(
        isBiometricEnabled: Bool = false,
        lastSyncDate: Date = .distantPast,
        priceColorMode: PriceColorMode = .korean
    ) {
        self.isBiometricEnabled = isBiometricEnabled
        self.lastSyncDate = lastSyncDate
        self.priceColorMode = priceColorMode
    }

    enum CodingKeys: String, CodingKey {
        case isBiometricEnabled
        case lastSyncDate
        case priceColorMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isBiometricEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBiometricEnabled) ?? false
        self.lastSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastSyncDate) ?? .distantPast
        self.priceColorMode = try container.decodeIfPresent(PriceColorMode.self, forKey: .priceColorMode) ?? .korean
    }
}
