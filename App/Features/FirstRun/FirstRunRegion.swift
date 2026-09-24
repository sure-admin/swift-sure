import Foundation

/// Market that selects first-run copy and showcase artwork. Wallet account
/// types, institutions, and currency differ by market, so each case resolves
/// its own `FirstRunMarket`; today every market shares the same content.
enum FirstRunRegion: String, CaseIterable, Sendable {
  case unitedStates = "US"
  case unitedKingdom = "UK"
  case other

  init(locale: Locale) {
    switch locale.region?.identifier {
    case "US": self = .unitedStates
    case "GB": self = .unitedKingdom
    default: self = .other
    }
  }
}
