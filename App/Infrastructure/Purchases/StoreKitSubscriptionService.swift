import Foundation
import StoreKit

@MainActor
final class StoreKitSubscriptionService: SubscriptionServicing {
  static let monthlyID = "am.sure.insights.sync.monthly"
  static let annualID = "am.sure.insights.sync.yearly"
  static let productIDs = [monthlyID, annualID]
  private var products: [Product] = []

  func plans() async throws -> [SubscriptionPlan] {
    products = try await Product.products(for: Self.productIDs)
    var result: [SubscriptionPlan] = []
    for product in products.sorted(by: { $0.price < $1.price }) {
      let eligible = await product.subscription?.isEligibleForIntroOffer ?? false
      let offer = product.subscription?.introductoryOffer
      result.append(SubscriptionPlan(id: product.id, price: product.displayPrice,
        isAnnual: product.id == Self.annualID,
        hasTrial: eligible && offer?.paymentMode == .freeTrial))
    }
    return result
  }

  func entitlement() async -> SubscriptionEntitlement? {
    var best: SubscriptionEntitlement?
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result,
            Self.productIDs.contains(transaction.productID),
            transaction.revocationDate == nil, !transaction.isUpgraded,
            let expiration = transaction.expirationDate else { continue }
      var end = expiration
      var cancelled = false
      if let status = await transaction.subscriptionStatus,
         case .verified(let renewal) = status.renewalInfo {
        cancelled = !renewal.willAutoRenew
        if status.state == .inGracePeriod, let grace = renewal.gracePeriodExpirationDate {
          end = grace
        }
      }
      guard end > Date() else { continue }
      if best == nil || end > best!.expiration {
        best = SubscriptionEntitlement(expiration: end, renewalCancelled: cancelled)
      }
    }
    return best
  }

  func purchase(_ id: String) async throws -> SubscriptionPurchaseOutcome {
    guard AppStore.canMakePayments,
          let product = products.first(where: { $0.id == id }) else {
      throw BackendAccessError.subscriptionRequired
    }
    switch try await product.purchase() {
    case .success(let result):
      guard case .verified(let transaction) = result else { throw BackendAccessError.subscriptionRequired }
      await transaction.finish()
      return .completed
    case .pending: return .pending
    case .userCancelled: return .cancelled
    @unknown default: throw BackendAccessError.subscriptionRequired
    }
  }

  func restore() async throws { try await AppStore.sync() }

  func observe(_ changed: @escaping @MainActor () async -> Void) async {
    for await result in Transaction.updates {
      guard !Task.isCancelled else { return }
      await changed()
      if case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID) {
        await transaction.finish()
      }
    }
  }
}
