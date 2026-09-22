import Foundation
import Observation

@MainActor @Observable
final class FinanceKitSyncStore {
  enum State: Equatable {
    case unavailable, idle, enrolling, active, syncing, importing, repairRequired, failed(String)
  }

  /// A tab switch or a quick app re-entry must not re-enter the runner. The
  /// process lock would serialise anyway, but losing that race is not a failure
  /// worth showing anyone.
  static let foregroundSyncInterval: TimeInterval = 60

  private(set) var state: State = .idle
  private(set) var health: FinanceKitConnectionRecord?
  private(set) var conflicts: [FinanceKitConflictRecord] = []
  private let client: FinanceKitControlPlaneClient
  private let publisher: any FinanceKitPublisherLifecycleHandling
  private let entitlement: FinanceKitBackgroundEntitlementReader
  private let runSync: @Sendable (Set<FinanceKitBackgroundDataType>) async throws -> FinanceKitSyncOutcome
  private let now: @Sendable () -> Date
  private var connectionID: UUID?
  private var lastForegroundSyncAt: Date?
  private var isSyncing = false

  init(client: FinanceKitControlPlaneClient, publisher: any FinanceKitPublisherLifecycleHandling,
       entitlement: FinanceKitBackgroundEntitlementReader = .init(),
       runSync: @escaping @Sendable (Set<FinanceKitBackgroundDataType>) async throws -> FinanceKitSyncOutcome = {
         try await FinanceKitSyncRunner().run(changedTypes: $0)
       },
       now: @escaping @Sendable () -> Date = { .now }) {
    self.client = client; self.publisher = publisher; self.entitlement = entitlement
    self.runSync = runSync; self.now = now
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
    } catch { state = .failed("Wallet sync couldn’t be enabled. Try again.") }
  }

  /// Collects everything since the checkpoint and uploads it. An empty hint set
  /// is the supported "collect everything" request, not a workaround.
  func sync() async {
    guard case .active = state else { return }
    state = .syncing
    isSyncing = true
    defer { isSyncing = false }
    do {
      _ = try await runSync([])
      await refresh()
    } catch FinanceKitSyncError.importPending {
      state = .importing
    } catch FinanceKitSyncError.streamFailed {
      await refresh()
    } catch FinanceKitProcessLockError.busy {
      // Another pass already holds the outbox; its result arrives on the next refresh.
      await refresh()
    } catch {
      state = .failed("Wallet sync couldn’t finish. Try again.")
    }
  }

  /// The scene-phase entry point: refreshes health, then syncs if this device is
  /// still a configured publisher and the last attempt is old enough.
  func syncOnForeground() async {
    guard !isSyncing else { return }
    let moment = now()
    if let last = lastForegroundSyncAt, moment.timeIntervalSince(last) < Self.foregroundSyncInterval { return }
    lastForegroundSyncAt = moment
    await refresh()
    guard case .active = state else { return }
    await sync()
  }

  func refresh() async {
    if connectionID == nil { connectionID = await publisher.configuredConnectionID() }
    guard let connectionID else { state = .idle; return }
    do {
      let value = try await client.health(connectionID: connectionID)
      health = value
      conflicts = try await client.conflicts(connectionID: connectionID).conflicts
      state = value.status == "repair_required" ? .repairRequired : .active
    } catch { state = .failed("Wallet sync status is unavailable.") }
  }

  func repair() async {
    guard let connectionID else { return }
    do {
      let activation = try await client.repair(connectionID: connectionID)
      try await publisher.install(configuration: activation.configuration(), credential: activation.publisherCredential)
      await refresh()
    } catch { state = .failed("Wallet sync repair failed.") }
  }

  func renew() async {
    guard let connectionID else { return }
    do {
      let activation = try await client.renew(connectionID: connectionID)
      try await publisher.install(configuration: activation.configuration(), credential: activation.publisherCredential)
      await refresh()
    } catch { state = .failed("Wallet sync credential renewal failed.") }
  }

  func resolve(_ conflict: FinanceKitConflictRecord, keepingSure: Bool) async {
    guard let connectionID else { return }
    do { _ = try await client.resolve(connectionID: connectionID, conflictID: conflict.id,
      resolution: keepingSure ? "keep_sure" : "retry_after_repair"); await refresh() }
    catch { state = .failed("The conflict couldn’t be resolved.") }
  }
}
enum FinanceKitControlPlaneError: Error { case missingBalance }
