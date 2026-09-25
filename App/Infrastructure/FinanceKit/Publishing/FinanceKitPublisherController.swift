import Foundation

#if os(iOS) && FINANCEKIT_ENABLED
import FinanceKit
#endif

actor FinanceKitPublisherController: FinanceKitPublisherLifecycleHandling {
  typealias RemoteUpdate = @Sendable (UUID) async throws -> (
    configuration: FinanceKitPublisherConfiguration, credential: String
  )

  private let makeCollector: @Sendable () -> any FinanceKitChangeCollecting
  private let remoteRenew: RemoteUpdate
  private let remoteRepair: RemoteUpdate
  private var gate: BackendAccessGate
  private nonisolated let makeEnvironment: @Sendable () throws -> FinanceKitPublisherEnvironment
  private nonisolated let makeCredentialStore: @Sendable (String) -> any FinanceKitPublisherCredentialStoring
  private let remoteDisconnect: @Sendable (FinanceKitDisconnectTarget) async throws -> Void

  init(
    gate: BackendAccessGate,
    makeCollector: @escaping @Sendable () -> any FinanceKitChangeCollecting = { FinanceKitHistoryChangeCollector() },
    makeEnvironment: @escaping @Sendable () throws -> FinanceKitPublisherEnvironment = {
      try FinanceKitPublisherEnvironment.live()
    },
    makeCredentialStore: @escaping @Sendable (String) -> any FinanceKitPublisherCredentialStoring = {
      FinanceKitPublisherCredentialStore(accessGroup: $0)
    },
    remoteRenew: @escaping RemoteUpdate = { _ in throw FinanceKitSyncError.invalidState },
    remoteRepair: @escaping RemoteUpdate = { _ in throw FinanceKitSyncError.invalidState },
    remoteDisconnect: @escaping @Sendable (FinanceKitDisconnectTarget) async throws -> Void = { _ in }
  ) {
    self.makeCollector = makeCollector
    self.remoteRenew = remoteRenew
    self.remoteRepair = remoteRepair
    self.gate = gate
    self.makeEnvironment = makeEnvironment
    self.remoteDisconnect = remoteDisconnect
    self.makeCredentialStore = makeCredentialStore
  }

  func install(
    configuration: FinanceKitPublisherConfiguration,
    credential: String
  ) async throws {
    try gate.check()
    let environment = try makeEnvironment()
    let stateStore = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    let credentialStore = makeCredentialStore(environment.keychainAccessGroup)
    let revocationStore = FinanceKitPublisherRevocationStore(
      fileURL: environment.revocationURL
    )

    do {
      let lock = try FinanceKitProcessLock(url: environment.lockURL).acquire()
      defer { _ = lock }
      let pendingDisconnections = try await stateStore.load().pendingDisconnections
      try credentialStore.removeAllCredentials()
      try credentialStore.saveCredential(credential, for: configuration.publisherID)
      var state = FinanceKitPublisherState.empty
      state.configuration = configuration
      state.pendingDisconnections = pendingDisconnections
      do {
        try await stateStore.save(state)
        try revocationStore.clear()
      } catch {
        try? credentialStore.removeAllCredentials()
        var cleanup = FinanceKitPublisherState.empty
        cleanup.pendingDisconnections = pendingDisconnections
        if pendingDisconnections?.isEmpty == false { try? await stateStore.save(cleanup) }
        else { try? await stateStore.clear() }
        throw error
      }
    }
    await resumeIfConfigured()
  }

  func renewCredential() async throws {
    try await updatePublisher(.renewal)
  }

  func repair() async throws {
    try await updatePublisher(.repair)
  }

  private enum PublisherUpdate { case renewal, repair }

  private func updatePublisher(_ operation: PublisherUpdate) async throws {
    try gate.check()
    let environment = try makeEnvironment()
    // Rotation invalidates the server's previous credential immediately. Hold the
    // same lock as uploads BEFORE the control-plane request, through installation.
    let lock = try FinanceKitProcessLock(url: environment.lockURL).acquire()
    defer { _ = lock }
    let revocation = FinanceKitPublisherRevocationStore(fileURL: environment.revocationURL)
    guard !revocation.isRevoked else { throw FinanceKitBatchUploadError.publisherRevoked }
    let store = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    var state = try await store.load()
    guard let previous = state.configuration else { throw FinanceKitSyncError.invalidState }
    if operation == .repair {
      // If repair succeeds remotely but local installation fails, do not send
      // the retained outbox into the replacement stream. A later repair can retry.
      state.requiresRepair = true
      try await store.save(state)
    }
    try gate.check()
    guard !revocation.isRevoked else { throw FinanceKitBatchUploadError.publisherRevoked }
    let update = try await (operation == .repair ? remoteRepair : remoteRenew)(previous.connectionID)
    try Task.checkCancellation()
    try gate.check()
    guard !revocation.isRevoked else { throw FinanceKitBatchUploadError.publisherRevoked }
    let configuration = update.configuration
    guard configuration.connectionID == previous.connectionID,
          configuration.publisherID == previous.publisherID,
          configuration.serverURL == previous.serverURL else { throw FinanceKitSyncError.invalidState }
    if operation == .repair {
      guard configuration.generation > previous.generation,
            configuration.streamID != previous.streamID else { throw FinanceKitSyncError.invalidState }
      let pendingDisconnections = state.pendingDisconnections
      state = .empty
      state.pendingDisconnections = pendingDisconnections
    } else {
      guard configuration.generation == previous.generation,
            configuration.streamID == previous.streamID,
            configuration.accountBindings == previous.accountBindings,
            configuration.consent == previous.consent else { throw FinanceKitSyncError.invalidState }
    }
    state.configuration = configuration
    // Renewal changes the secret, not the stream. Retain exact pending bytes,
    // sequence, digest chain, and checkpoint so a rejected batch is replayable.
    try makeCredentialStore(environment.keychainAccessGroup)
      .saveCredential(update.credential, for: configuration.publisherID)
    try await store.save(state)
  }

  func configuredConnectionID() async -> UUID? {
    guard let environment = try? makeEnvironment(),
          let state = try? await FinanceKitPublisherStateFileStore(
            fileURL: environment.stateURL
          ).load() else { return nil }
    guard !FinanceKitPublisherRevocationStore(fileURL: environment.revocationURL).isRevoked,
          let configuration = state.configuration,
          (try? makeCredentialStore(environment.keychainAccessGroup).credential(for: configuration.publisherID)) != nil
    else { return nil }
    return configuration.connectionID
  }

  func requiresRepair() async -> Bool {
    guard let environment = try? makeEnvironment(),
          let state = try? await FinanceKitPublisherStateFileStore(fileURL: environment.stateURL).load()
    else { return false }
    return state.requiresRepair
  }

  func batchRejection() async -> FinanceKitBatchRejection? {
    guard let environment = try? makeEnvironment(),
          let state = try? await FinanceKitPublisherStateFileStore(fileURL: environment.stateURL).load()
    else { return nil }
    return state.batchRejection
  }

  func batchValidationIssue() async -> FinanceKitEventValidationIssue? {
    guard let environment = try? makeEnvironment(),
          !FinanceKitPublisherRevocationStore(fileURL: environment.revocationURL).isRevoked,
          let state = try? await FinanceKitPublisherStateFileStore(fileURL: environment.stateURL).load(),
          state.batchRejection != nil, let batch = state.pendingCapture?.currentBatch else { return nil }
    return FinanceKitRejectedBatchInspector().inspect(batch.body)
  }

  func resumeIfConfigured() async {
    guard gate.isAllowed else {
      await suspend()
      return
    }
    let environment: FinanceKitPublisherEnvironment
    let stateStore: FinanceKitPublisherStateFileStore
    let revocationStore: FinanceKitPublisherRevocationStore
    let credentialStore: any FinanceKitPublisherCredentialStoring
    do {
      environment = try makeEnvironment()
      revocationStore = FinanceKitPublisherRevocationStore(
        fileURL: environment.revocationURL
      )
      guard !revocationStore.isRevoked else { throw FinanceKitBatchUploadError.publisherRevoked }
      stateStore = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
      let state = try await stateStore.load()
      credentialStore = makeCredentialStore(environment.keychainAccessGroup)
      guard state.configuration != nil else { throw FinanceKitSyncError.invalidState }
    } catch {
      disableBackgroundDelivery()
      return
    }

    enableBackgroundDelivery()
    let uploadGate = gate
    do {
      let engine = FinanceKitSyncEngine(
        stateStore: stateStore,
        collector: makeCollector(),
        makeUploader: { configuration in
          guard !revocationStore.isRevoked else { throw FinanceKitBatchUploadError.publisherRevoked }
          guard let credential = try credentialStore.credential(for: configuration.publisherID) else {
            throw FinanceKitSyncError.invalidState
          }
          return FinanceKitHTTPBatchUploader.live(
            gate: uploadGate,
            credential: credential,
            canUpload: {
              !revocationStore.isRevoked &&
                (try? credentialStore.credential(for: configuration.publisherID)) == credential
            }
          )
        },
        processLock: FinanceKitProcessLock(url: environment.lockURL)
      )
      _ = try await engine.synchronize()
    } catch {
      // Background delivery can retry durable state; local Wallet access remains independent.
    }
  }

  func suspend() async {
    disableBackgroundDelivery()
  }

  nonisolated func blockBackgroundDelivery() throws {
    disableBackgroundDelivery()
    let environment = try makeEnvironment()
    do {
      try FinanceKitPublisherRevocationStore(fileURL: environment.revocationURL).revoke()
    } catch {
      // Every request also checks the shared credential, including already-built uploaders.
      // Keychain invalidation is the fail-closed fallback if the marker cannot be persisted.
      try makeCredentialStore(environment.keychainAccessGroup).removeAllCredentials()
    }
  }

  func hasPendingConsentWithdrawal() async -> Bool {
    guard let environment = try? makeEnvironment(),
          let state = try? await FinanceKitPublisherStateFileStore(fileURL: environment.stateURL).load()
    else { return false }
    return state.consentWithdrawalPending == true
  }

  func stopKeepingHistory() async throws {
    try await disconnect(consentWithdrawal: true)
  }

  func disconnect() async throws {
    try await disconnect(consentWithdrawal: false)
  }

  private func disconnect(consentWithdrawal: Bool) async throws {
    // Revocation and credential removal remain authoritative even when offline.
    var failure: (any Error)?
    do { try blockBackgroundDelivery() } catch { failure = error }
    let environment = try makeEnvironment()
    let lock = try FinanceKitProcessLock(url: environment.lockURL).acquire()
    defer { _ = lock }
    let store = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    var targets: [FinanceKitDisconnectTarget] = []
    do {
      let previous = try await store.load()
      targets = previous.pendingDisconnections ?? []
      if let configuration = previous.configuration {
        let target = FinanceKitDisconnectTarget(connectionID: configuration.connectionID, serverURL: configuration.serverURL)
        if !targets.contains(target) { targets.append(target) }
      }
    } catch { failure = error }
    do { try makeCredentialStore(environment.keychainAccessGroup).removeAllCredentials() }
    catch { failure = error }

    // Persist retry targets before sending DELETE. This also covers termination
    // or a lost response, without retaining consent, account IDs or financial data.
    do { try await saveDisconnections(targets, consentWithdrawal: consentWithdrawal, to: store) }
    catch {
      failure = error
      // If minimal-state persistence fails, still attempt to remove financial state.
      try? await store.clear()
    }
    for target in targets {
      do {
        try await remoteDisconnect(target)
        targets.removeAll { $0 == target }
        try await saveDisconnections(targets, consentWithdrawal: consentWithdrawal, to: store)
      } catch { if failure == nil { failure = error } }
    }
    if let failure { throw failure }
  }

  private func saveDisconnections(_ targets: [FinanceKitDisconnectTarget], consentWithdrawal: Bool,
                                 to store: FinanceKitPublisherStateFileStore) async throws {
    guard !targets.isEmpty else { try await store.clear(); return }
    var state = FinanceKitPublisherState.empty
    state.pendingDisconnections = targets
    state.consentWithdrawalPending = consentWithdrawal ? true : nil
    try await store.save(state)
  }

  private func enableBackgroundDelivery() {
    #if os(iOS) && FINANCEKIT_ENABLED && !targetEnvironment(simulator)
    if #available(iOS 26.0, *) {
      FinanceStore.shared.enableBackgroundDelivery(
        for: [.accounts, .accountBalances, .transactions],
        frequency: .hourly
      )
    }
    #endif
  }

  private nonisolated func disableBackgroundDelivery() {
    #if os(iOS) && FINANCEKIT_ENABLED && !targetEnvironment(simulator)
    if #available(iOS 26.0, *) {
      FinanceStore.shared.disableAllBackgroundDelivery()
    }
    #endif
  }
}
