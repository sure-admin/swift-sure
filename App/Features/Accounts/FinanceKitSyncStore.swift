import Foundation
import Observation

@MainActor @Observable
final class FinanceKitSyncStore {
  enum State: Equatable { case unavailable, idle, enrolling, active, repairRequired, failed(String) }
  private(set) var state: State = .idle
  private(set) var health: FinanceKitConnectionRecord?
  private(set) var conflicts: [FinanceKitConflictRecord] = []
  private let client: FinanceKitControlPlaneClient
  private let publisher: any FinanceKitPublisherLifecycleHandling
  private let entitlement: FinanceKitBackgroundEntitlementReader
  private var connectionID: UUID?

  init(client: FinanceKitControlPlaneClient, publisher: any FinanceKitPublisherLifecycleHandling,
       entitlement: FinanceKitBackgroundEntitlementReader = .init()) {
    self.client = client; self.publisher = publisher; self.entitlement = entitlement
  }

  func enroll(accounts: [LocalFinancialAccount]) async {
    guard !accounts.isEmpty else { state = .failed("Choose at least one Wallet account."); return }
    state = .enrolling
    do {
      guard await entitlement.expiration() != nil, try await client.capabilities().available else {
        state = .unavailable; return
      }
      let ids = accounts.map(\.id)
      let consent = try FinanceKitUploadConsent(grantedAt: .now, selectedSourceAccountIDs: ids,
        uploadAuthorized: true, familyVisibilityAcknowledged: true, remoteProcessingAcknowledged: true)
      let connection = try await client.enroll(.init(enrollmentID: UUID(), consent: consent))
      connectionID = connection.connectionID
      for account in accounts {
        guard let balance = account.balance else { throw FinanceKitControlPlaneError.missingBalance }
        let decimal = balance.decimalValue
        let amount = NSDecimalNumber(decimal: decimal < 0 ? -decimal : decimal).stringValue
        _ = try await client.map(connectionID: connection.connectionID, account: .init(sourceID: account.id,
          body: .init(name: account.name, institutionName: account.institutionName,
            currency: balance.currency.rawValue, accountableType: account.kind == .asset ? "Depository" : "CreditCard",
            subtype: account.kind == .asset ? "checking" : "credit_card", ledgerTimezone: TimeZone.autoupdatingCurrent.identifier,
            bookedBalance: .init(amount: amount, currency: balance.currency.rawValue,
              direction: balance.decimalValue < 0 ? "debit" : "credit"), observedAt: .now)))
      }
      let activation = try await client.activate(connectionID: connection.connectionID)
      try await publisher.install(configuration: activation.configuration(), credential: activation.publisherCredential)
      await refresh()
    } catch { state = .failed("Finance sync couldn’t be enabled. Try again.") }
  }

  func refresh() async {
    guard let connectionID else { state = .idle; return }
    do {
      let value = try await client.health(connectionID: connectionID)
      health = value
      conflicts = try await client.conflicts(connectionID: connectionID).conflicts
      state = value.status == "repair_required" ? .repairRequired : .active
    } catch { state = .failed("Finance sync status is unavailable.") }
  }

  func repair() async {
    guard let connectionID else { return }
    do {
      let activation = try await client.repair(connectionID: connectionID)
      try await publisher.install(configuration: activation.configuration(), credential: activation.publisherCredential)
      await refresh()
    } catch { state = .failed("Finance sync repair failed.") }
  }

  func renew() async {
    guard let connectionID else { return }
    do {
      let activation = try await client.renew(connectionID: connectionID)
      try await publisher.install(configuration: activation.configuration(), credential: activation.publisherCredential)
      await refresh()
    } catch { state = .failed("Finance sync credential renewal failed.") }
  }

  func resolve(_ conflict: FinanceKitConflictRecord, keepingSure: Bool) async {
    guard let connectionID else { return }
    do { _ = try await client.resolve(connectionID: connectionID, conflictID: conflict.id,
      resolution: keepingSure ? "keep_sure" : "retry_after_repair"); await refresh() }
    catch { state = .failed("The conflict couldn’t be resolved.") }
  }
}
enum FinanceKitControlPlaneError: Error { case missingBalance }
