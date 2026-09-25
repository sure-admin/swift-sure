import Foundation

/// Region-specific inputs to first-run copy and artwork.
struct FirstRunMarket: Sendable {
  /// Wallet sources named in the Wallet pitch, e.g. "Apple Card and Apple Cash".
  var walletSources: String
  /// Wallet products listed when this iPhone has no shareable accounts yet.
  var walletProducts: String
  var showcase: FirstRunShowcase

  // UK FinanceKit exposes Open Banking accounts (e.g. Monzo, Barclaycard) and
  // will need its own names, currency, and artwork. Until that copy is
  // approved, every region intentionally resolves to the same content.
  static func market(for region: FirstRunRegion) -> FirstRunMarket {
    switch region {
    case .unitedStates, .unitedKingdom, .other:
      return .standard
    }
  }

  static let standard = FirstRunMarket(
    walletSources: String(localized: "first_run.wallet.sources", table: "FirstRun"),
    walletProducts: String(localized: "first_run.wallet.products", table: "FirstRun"),
    showcase: .standard
  )
}
