import SwiftUI

/// Presentation-layer brand metadata for each exchange.
///
/// Used by `ExchangeBadge` to render either a bundled logo asset or a
/// brand-colored monogram circle fallback. Swapping logos for monograms
/// is a kill-switch: delete the imageset from
/// `Assets.xcassets/Logo/` and the badge automatically reverts to the
/// monogram path without any code changes.
extension Exchange {

    /// Representative brand color. Used as the monogram circle background
    /// and as a general accent for exchange-themed UI.
    var brandColor: Color {
        switch self {
        case .upbit:   return Color(red: 0.00, green: 0.40, blue: 0.94)
        case .binance: return Color(red: 0.94, green: 0.73, blue: 0.00)
        case .bithumb: return Color(red: 0.95, green: 0.38, blue: 0.00)
        case .bybit:   return Color(red: 0.95, green: 0.75, blue: 0.14)
        case .coinone: return Color(red: 0.09, green: 0.21, blue: 0.52)
        case .korbit:  return Color(red: 0.00, green: 0.55, blue: 0.85)
        case .okx:     return Color.black
        }
    }

    /// 1–2 character abbreviation used in the monogram fallback.
    var monogram: String {
        switch self {
        case .upbit:   return "U"
        case .binance: return "B"
        case .bithumb: return "Bt"
        case .bybit:   return "By"
        case .coinone: return "Co"
        case .korbit:  return "K"
        case .okx:     return "OK"
        }
    }

    /// Name of the bundled image asset for this exchange's logo. The name
    /// is resolved against `Logo/` inside `Assets.xcassets`, which uses
    /// `provides-namespace: true`, so the full asset name is
    /// `"Logo/<exchange>"`. If the asset is missing, `ExchangeBadge`
    /// falls back to the monogram circle.
    var logoAssetName: String { "Logo/\(rawValue.lowercased())" }
}
