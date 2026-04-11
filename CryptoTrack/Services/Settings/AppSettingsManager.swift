import Foundation
import Observation

/// UserDefaults에 저장되는 표시 설정의 관찰 가능한 단일 진입점.
/// API 키나 기기 비밀은 저장하지 않는다 — 순수 UI/표시 옵션만.
@Observable
@MainActor
final class AppSettingsManager {

    static let shared = AppSettingsManager()

    var priceColorMode: PriceColorMode {
        didSet {
            UserDefaults.standard.set(priceColorMode.rawValue, forKey: Self.priceColorModeKey)
        }
    }

    private static let priceColorModeKey = "settings.priceColorMode"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.priceColorModeKey),
           let mode = PriceColorMode(rawValue: raw) {
            self.priceColorMode = mode
        } else {
            self.priceColorMode = .korean
        }
    }
}
