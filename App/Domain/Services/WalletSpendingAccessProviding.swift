import Foundation

@MainActor
protocol WalletSpendingAccessProviding: AnyObject {
  var walletSpendingAccess: WalletSpendingAccess { get }
}

struct WalletSpendingAccess: Equatable, Sendable {
  var isAuthorized: Bool
  var accountIDs: Set<UUID>
  var currencies: Set<CurrencyCode>
  var generation: Int
}
