import Foundation
import Testing
@testable import Sure

@MainActor
struct SubscriptionAccessStoreTests {
  @Test func pendingAndCancelledPurchasesStayLocked() async {
    for outcome in [SubscriptionPurchaseOutcome.pending, .cancelled] {
      let service = PurchaseServiceFake()
      service.outcome = outcome
      let store = SubscriptionAccessStore(service: service, gate: BackendAccessGate(), waitUntil: { _ in throw CancellationError() })
      await store.refresh()
      await store.purchase(SubscriptionPlan(id: "monthly", price: "$0.99", isAnnual: false, hasTrial: true))
      #expect(!store.hasAccess)
      #expect(!store.gate.isAllowed)
    }
  }

  @Test func cancellationKeepsPaidAccessAndExpirationLocks() async {
    let now = Date(timeIntervalSince1970: 100)
    let service = PurchaseServiceFake()
    let store = SubscriptionAccessStore(service: service, gate: BackendAccessGate(now: { now }), waitUntil: { _ in throw CancellationError() })
    service.value = SubscriptionEntitlement(expiration: .distantFuture, renewalCancelled: true)
    await store.refresh()
    #expect(store.hasAccess)
    #expect(store.renewalCancelled)
    service.value = nil
    await store.refresh()
    #expect(!store.hasAccess)
  }

  @Test func restoringVerifiedSharedAccessUnlocks() async {
    let service = PurchaseServiceFake()
    let store = SubscriptionAccessStore(service: service, gate: BackendAccessGate(), waitUntil: { _ in throw CancellationError() })
    service.value = SubscriptionEntitlement(expiration: .distantFuture, renewalCancelled: false)
    await store.restore()
    #expect(store.hasAccess)
    #expect(service.restored)
  }
}

@MainActor
private final class PurchaseServiceFake: SubscriptionServicing {
  var value: SubscriptionEntitlement?
  var outcome: SubscriptionPurchaseOutcome = .cancelled
  var restored = false
  func plans() async throws -> [SubscriptionPlan] { [] }
  func entitlement() async -> SubscriptionEntitlement? { value }
  func purchase(_ id: String) async throws -> SubscriptionPurchaseOutcome { outcome }
  func restore() async throws { restored = true }
  func observe(_ changed: @escaping @MainActor () async -> Void) async { }
}
