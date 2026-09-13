import Foundation

@MainActor
protocol SubscriptionServicing {
  func plans() async throws -> [SubscriptionPlan]
  func entitlement() async -> SubscriptionEntitlement?
  func purchase(_ id: String) async throws -> SubscriptionPurchaseOutcome
  func restore() async throws
  func observe(_ changed: @escaping @MainActor () async -> Void) async
}

struct SubscriptionPlan: Identifiable {
  var id: String
  var price: String
  var isAnnual: Bool
  var trialDuration: String? = nil
  var title: String = ""
  var billingPeriod: String = ""
  var monthlyEquivalent: String? = nil
  var savingsPercent: Int? = nil
  var familyShareable: Bool = false
  var hasTrial: Bool { trialDuration != nil }
}

struct SubscriptionEntitlement {
  var expiration: Date
  var renewalCancelled: Bool
}

enum SubscriptionPurchaseOutcome { case completed, pending, cancelled }
