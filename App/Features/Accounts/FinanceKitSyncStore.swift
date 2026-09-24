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

  private(set) var consentAcknowledged: Bool
  var showsConsentWithdrawalConfirmation = false
  private(set) var needsDisconnectRetry = false
  private let preferences: any FinanceKitSyncPreferences
  private(set) var state: State = .idle
  private(set) var batchValidationIssue: FinanceKitEventValidationIssue?
  private(set) var batchRejection: FinanceKitBatchRejection?
  var rejectionMessage: String? {
    guard let batchRejection else { return nil }
    let reason = batchRejection == .unknown ? "unrecognized protocol error" : batchRejection.rawValue
    if let issue = batchValidationIssue {
      let location = issue.eventIndex.map { "events[\($0)].\(issue.field.rawValue)" } ?? issue.field.rawValue
      let rule: String = switch issue.rule {
      case .requiredForBooked: "A booked transaction has no posting date. Sure requires posted_at."
      case .nonblank: "Sure requires nonblank text."
      case .textLimit(let limit): "Text exceeds Sure’s limit of \(limit) Unicode code points."
      case .supportedStatus: "The transaction status is not supported by Sure."
      case .notAfterCapture: "The timestamp is later than captured_at."
      case .uniqueIdentity: "This record identity appears more than once in the batch."
      case .readablePayload: "The saved batch could not be decoded for local inspection."
      }
      return "Sure rejected a Wallet batch (HTTP 422: \(reason)). Local check: \(location). \(rule) Uploads remain paused. Report this diagnostic before repairing again."
    }
    return "Sure rejected a Wallet batch (HTTP 422: \(reason)). Automatic retries are paused. Repair starts a new Wallet snapshot; if the error returns, report this code."
  }
  private(set) var health: FinanceKitConnectionRecord?
  private(set) var conflicts: [FinanceKitConflictRecord] = []
  private let client: FinanceKitControlPlaneClient
  private let publisher: any FinanceKitPublisherLifecycleHandling
  private let entitlementExpiration: @Sendable () async -> Date?
  private let makeID: @Sendable () -> UUID
  private let runSync: @Sendable (Set<FinanceKitBackgroundDataType>) async throws -> FinanceKitSyncOutcome
  private let now: @Sendable () -> Date
  private var enrollmentInProgress = false
  private var pendingEnrollmentCleanup: UUID?
  private var localRepairRequired = false
  private var lastForegroundSyncAt: Date?
  private var isSyncing = false
  private var isUpdatingPublisher = false
  var isBusy: Bool { enrollmentInProgress || isSyncing || isUpdatingPublisher }

  init(client: FinanceKitControlPlaneClient, publisher: any FinanceKitPublisherLifecycleHandling,
       preferences: any FinanceKitSyncPreferences,
       entitlementExpiration: @escaping @Sendable () async -> Date? = {
         await FinanceKitBackgroundEntitlementReader().expiration()
       },
       makeID: @escaping @Sendable () -> UUID = { UUID() },
       runSync: @escaping @Sendable (Set<FinanceKitBackgroundDataType>) async throws -> FinanceKitSyncOutcome = {
         try await FinanceKitSyncRunner().run(changedTypes: $0)
       },
       now: @escaping @Sendable () -> Date = { .now }) {
    self.preferences = preferences
    self.consentAcknowledged = preferences.consentAcknowledged ?? false
    self.needsDisconnectRetry = preferences.consentWithdrawalPending
    self.client = client; self.publisher = publisher
    self.entitlementExpiration = entitlementExpiration; self.makeID = makeID
    self.runSync = runSync; self.now = now
  }

  func requestConsentChange(_ enabled: Bool) {
    guard !isBusy, !needsDisconnectRetry else { return }
    if enabled {
      consentAcknowledged = true
      preferences.consentAcknowledged = true
    } else if consentAcknowledged {
      showsConsentWithdrawalConfirmation = true
    }
  }

  func stopKeepingHistory() async {
    guard !isBusy else { return }
    showsConsentWithdrawalConfirmation = false
    isUpdatingPublisher = true
    defer { isUpdatingPublisher = false }
    do {
      // Revoke locally before persisting the off choice, including when offline.
      try publisher.blockBackgroundDelivery()
      consentAcknowledged = false
      preferences.consentAcknowledged = false
      needsDisconnectRetry = true
      preferences.consentWithdrawalPending = true
      try await publisher.stopKeepingHistory()
      needsDisconnectRetry = false
      preferences.consentWithdrawalPending = false
      clearStatus()
    } catch {
      state = .failed(consentAcknowledged
        ? "Wallet sync couldn’t be stopped. Try again."
        : "Wallet uploads are stopped on this device. Sure hasn’t confirmed disconnection. Retry to finish; synchronized transactions will be kept.")
    }
  }

  func enroll(accounts: [LocalFinancialAccount]) async {
    guard !isBusy, consentAcknowledged, !needsDisconnectRetry else { return }
    enrollmentInProgress = true
    defer { enrollmentInProgress = false }
    state = .enrolling
    var createdConnectionID: UUID?
    do {
      // Durable configuration is authoritative, even before the first view refresh.
      if await publisher.configuredConnectionID() != nil {
        await refreshStatus()
        return
      }
      if let pendingEnrollmentCleanup {
        try await client.disconnect(connectionID: pendingEnrollmentCleanup)
        self.pendingEnrollmentCleanup = nil
      }
      let moment = now()
      let consent = try FinanceKitUploadConsent(grantedAt: moment, selectedSourceAccountIDs: accounts.map(\.id),
        uploadAuthorized: true, familyVisibilityAcknowledged: true, remoteProcessingAcknowledged: true)
      let mappings = try accounts.map { account -> FinanceKitAccountMappingRequest in
        guard let balance = account.balance else { throw FinanceKitControlPlaneError.missingBalance }
        let decimal = balance.decimalValue
        let amount = NSDecimalNumber(decimal: decimal < 0 ? -decimal : decimal).stringValue
        return .init(sourceID: account.id,
          body: .init(name: account.name, institutionName: account.institutionName,
            currency: balance.currency.rawValue, accountableType: account.kind == .asset ? "Depository" : "CreditCard",
            subtype: account.kind == .asset ? "checking" : "credit_card", ledgerTimezone: TimeZone.autoupdatingCurrent.identifier,
            bookedBalance: .init(amount: amount, currency: balance.currency.rawValue,
              direction: decimal < 0 ? "debit" : "credit"), observedAt: moment))
      }
      guard await entitlementExpiration() != nil, try await client.capabilities().available else {
        state = .unavailable; return
      }
      let connection = try await client.enroll(.init(enrollmentID: makeID(), consent: consent))
      createdConnectionID = connection.connectionID
      for mapping in mappings {
        _ = try await client.map(connectionID: connection.connectionID, account: mapping)
      }
      let activation = try await client.activate(connectionID: connection.connectionID)
      try await publisher.install(configuration: activation.configuration(), credential: activation.publisherCredential)
      localRepairRequired = false
      await refreshStatus()
    } catch {
      if let createdConnectionID {
        pendingEnrollmentCleanup = createdConnectionID
        do {
          try await client.disconnect(connectionID: createdConnectionID)
          pendingEnrollmentCleanup = nil
        } catch {
          state = .failed("Wallet sync setup couldn’t be removed from Sure. Try again to finish cleanup.")
          return
        }
      }
      state = .failed("Wallet sync couldn’t be enabled. Try again.")
    }
  }

  /// Collects everything since the checkpoint and uploads it. An empty hint set
  /// is the supported "collect everything" request, not a workaround.
  func sync() async {
    guard !isBusy, consentAcknowledged, !needsDisconnectRetry, case .active = state else { return }
    state = .syncing
    isSyncing = true
    defer { isSyncing = false }
    do {
      switch try await syncWithCredentialRecovery() {
      case .repairRequired:
        localRepairRequired = true
        batchRejection = await publisher.batchRejection()
        batchValidationIssue = await publisher.batchValidationIssue()
        state = .repairRequired
      case .notConfigured:
        clearStatus()
      case .uploaded, .noChanges:
        await refreshStatus()
      case .busy:
        state = .active
      }
    } catch let error as FinanceKitBatchUploadError where error.kind == .rejected {
      batchRejection = FinanceKitBatchRejection(serverCode: error.code)
      batchValidationIssue = await publisher.batchValidationIssue()
      localRepairRequired = true
      state = .repairRequired
    } catch FinanceKitSyncError.importPending {
      state = .importing
    } catch FinanceKitSyncError.streamFailed {
      await refreshStatus()
    } catch FinanceKitProcessLockError.busy {
      // Another pass already holds the outbox; its result arrives on the next refresh.
      await refreshStatus()
    } catch {
      state = .failed("Wallet sync couldn’t finish. Try again.")
    }
  }

  private func syncWithCredentialRecovery() async throws -> FinanceKitSyncOutcome {
    do {
      return try await runSync([])
    } catch let error as FinanceKitBatchUploadError where error == .publisherUnauthorized {
      try Task.checkCancellation()
      // Only the dedicated publisher credential is renewed; never refresh OAuth
      // or re-enroll. A second rejection escapes without another rotation loop.
      try await publisher.renewCredential()
      return try await runSync([])
    }
  }

  /// The scene-phase entry point: refreshes health, then syncs if this device is
  /// still a configured publisher and the last attempt is old enough.
  func syncOnForeground() async {
    guard !isBusy, !showsConsentWithdrawalConfirmation else { return }
    let moment = now()
    if let last = lastForegroundSyncAt, moment.timeIntervalSince(last) < Self.foregroundSyncInterval { return }
    lastForegroundSyncAt = moment
    await refresh()
    guard case .active = state else { return }
    await sync()
  }

  func refresh() async {
    guard !isBusy else { return }
    await refreshStatus()
  }

  private func refreshStatus() async {
    let pendingWithdrawal = await publisher.hasPendingConsentWithdrawal()
    if needsDisconnectRetry || pendingWithdrawal {
      needsDisconnectRetry = true
      consentAcknowledged = false
      preferences.consentAcknowledged = false
      state = .failed("Wallet uploads are stopped on this device. Retry to finish disconnecting from Sure; synchronized transactions will be kept.")
      return
    }
    guard let connectionID = await publisher.configuredConnectionID() else { clearStatus(); return }
    if preferences.consentAcknowledged == nil {
      consentAcknowledged = true
      preferences.consentAcknowledged = true
    }
    guard !localRepairRequired, !(await publisher.requiresRepair()) else {
      if let rejection = await publisher.batchRejection() { batchRejection = rejection }
      batchValidationIssue = await publisher.batchValidationIssue()
      state = .repairRequired
      return
    }
    do {
      let value = try await client.health(connectionID: connectionID)
      let conflicts = try await client.conflicts(connectionID: connectionID).conflicts
      guard await publisher.configuredConnectionID() == connectionID else { clearStatus(); return }
      health = value
      self.conflicts = conflicts
      state = value.status == "repair_required" ? .repairRequired : .active
    } catch { state = .failed("Wallet sync status is unavailable.") }
  }

  private func clearStatus() {
    health = nil
    batchValidationIssue = nil
    batchRejection = nil
    conflicts = []
    localRepairRequired = false
    lastForegroundSyncAt = nil
    state = .idle
  }

  func repair() async {
    guard !isBusy else { return }
    isUpdatingPublisher = true
    defer { isUpdatingPublisher = false }
    guard await publisher.configuredConnectionID() != nil else { clearStatus(); return }
    do {
      try await publisher.repair()
      batchValidationIssue = nil
      batchRejection = nil
      localRepairRequired = false
      await refreshStatus()
    } catch { state = .failed("Wallet sync repair failed.") }
  }

  func renew() async {
    guard !isBusy else { return }
    isUpdatingPublisher = true
    defer { isUpdatingPublisher = false }
    guard await publisher.configuredConnectionID() != nil else { clearStatus(); return }
    do {
      try await publisher.renewCredential()
      await refreshStatus()
    } catch { state = .failed("Wallet sync credential renewal failed.") }
  }

  func resolve(_ conflict: FinanceKitConflictRecord, keepingSure: Bool) async {
    guard !isBusy else { return }
    guard let connectionID = await publisher.configuredConnectionID() else { clearStatus(); return }
    do { _ = try await client.resolve(connectionID: connectionID, conflictID: conflict.id,
      resolution: keepingSure ? "keep_sure" : "retry_after_repair"); await refresh() }
    catch { state = .failed("The conflict couldn’t be resolved.") }
  }
}
enum FinanceKitControlPlaneError: Error { case missingBalance }
