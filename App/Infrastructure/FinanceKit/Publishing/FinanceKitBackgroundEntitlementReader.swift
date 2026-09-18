import Foundation
import StoreKit

struct FinanceKitBackgroundEntitlementReader: Sendable {
  var now: @Sendable () -> Date = { Date() }

  func expiration() async -> Date? {
    var latest: Date?
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result,
            SubscriptionProductIDs.all.contains(transaction.productID),
            transaction.revocationDate == nil,
            !transaction.isUpgraded,
            let productExpiration = transaction.expirationDate else { continue }
      var expiration = productExpiration
      if let status = await transaction.subscriptionStatus,
         status.state == .inGracePeriod,
         case .verified(let renewal) = status.renewalInfo,
         let graceExpiration = renewal.gracePeriodExpirationDate {
        expiration = graceExpiration
      }
      guard expiration > now() else { continue }
      if latest == nil || expiration > latest! { latest = expiration }
    }
    return latest
  }
}
