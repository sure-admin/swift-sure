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
    let monthly = products.first {
      $0.subscription?.subscriptionPeriod.unit == .month
        && $0.subscription?.subscriptionPeriod.value == 1
    }
    for product in products {
      guard let subscription = product.subscription else { continue }
      let period = subscription.subscriptionPeriod
      let annual = period.unit == .year && period.value == 1
      let eligible = await subscription.isEligibleForIntroOffer
      let offer = subscription.introductoryOffer
      let trial = eligible && offer?.paymentMode == .freeTrial
        ? offer.map { Self.duration($0.period, count: $0.periodCount) } : nil
      let savings: Int?
      if annual, let monthly, monthly.price > 0,
         monthly.priceFormatStyle.currencyCode == product.priceFormatStyle.currencyCode {
        savings = Self.savings(annual: product.price, monthly: monthly.price)
      } else {
        savings = nil
      }
      result.append(SubscriptionPlan(
        id: product.id, price: product.displayPrice, isAnnual: annual,
        trialDuration: trial,
        title: annual ? String(localized: "Yearly") :
          (period.unit == .month && period.value == 1 ? String(localized: "Monthly") : product.displayName),
        billingPeriod: Self.duration(period),
        monthlyEquivalent: annual ? (product.price / 12).formatted(product.priceFormatStyle) : nil,
        savingsPercent: savings, familyShareable: product.isFamilyShareable
      ))
    }
    result.sort { lhs, rhs in
      if lhs.isAnnual != rhs.isAnnual { return lhs.isAnnual }
      return lhs.id < rhs.id
    }
    return result
  }

  static func savings(annual: Decimal, monthly: Decimal) -> Int? {
    guard monthly > 0, annual >= 0 else { return nil }
    let percent = (1 - annual / (monthly * 12)) * 100
    var value = percent
    var rounded = Decimal.zero
    NSDecimalRound(&rounded, &value, 0, .plain)
    let result = NSDecimalNumber(decimal: rounded).intValue
    return result > 0 ? result : nil
  }

  private static func duration(_ period: Product.SubscriptionPeriod, count: Int = 1) -> String {
    var components = DateComponents()
    let value = period.value * count
    switch period.unit {
    case .day: components.day = value
    case .week: components.weekOfMonth = value
    case .month: components.month = value
    case .year: components.year = value
    @unknown default: return String(localized: "subscription period")
    }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    return formatter.string(from: components) ?? String(localized: "subscription period")
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
