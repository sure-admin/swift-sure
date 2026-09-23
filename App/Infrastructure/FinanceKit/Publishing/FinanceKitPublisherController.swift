import Foundation

#if os(iOS) && FINANCEKIT_ENABLED
import FinanceKit
#endif

actor FinanceKitPublisherController: FinanceKitPublisherLifecycleHandling {
  private var gate: BackendAccessGate
  private nonisolated let makeEnvironment: @Sendable () throws -> FinanceKitPublisherEnvironment
  private nonisolated let makeCredentialStore: @Sendable (String) -> any FinanceKitPublisherCredentialStoring
  private let remoteDisconnect: @Sendable (UUID) async throws -> Void

  init(
    gate: BackendAccessGate,
    makeEnvironment: @escaping @Sendable () throws -> FinanceKitPublisherEnvironment = {
      try FinanceKitPublisherEnvironment.live()
    },
    makeCredentialStore: @escaping @Sendable (String) -> any FinanceKitPublisherCredentialStoring = {
      FinanceKitPublisherCredentialStore(accessGroup: $0)
    },
    remoteDisconnect: @escaping @Sendable (UUID) async throws -> Void = { _ in }
  ) {
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
      try credentialStore.removeAllCredentials()
      try credentialStore.saveCredential(credential, for: configuration.publisherID)
      var state = FinanceKitPublisherState.empty
      state.configuration = configuration
      do {
        try await stateStore.save(state)
        try revocationStore.clear()
      } catch {
        try? credentialStore.removeAllCredentials()
        try? await stateStore.clear()
        throw error
      }
    }
    await resumeIfConfigured()
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

  func resumeIfConfigured() async {
    guard gate.isAllowed else {
      await suspend()
      return
    }
    let environment: FinanceKitPublisherEnvironment
    let stateStore: FinanceKitPublisherStateFileStore
    let revocationStore: FinanceKitPublisherRevocationStore
    let credential: String
    let publisherID: UUID
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
      guard let configuredPublisher = state.configuration,
            let storedCredential = try credentialStore.credential(for: configuredPublisher.publisherID) else { throw FinanceKitSyncError.invalidState }
      credential = storedCredential
      publisherID = configuredPublisher.publisherID
    } catch {
      disableBackgroundDelivery()
      return
    }

    enableBackgroundDelivery()
    do {
      let engine = FinanceKitSyncEngine(
        stateStore: stateStore,
        collector: FinanceKitHistoryChangeCollector(),
        uploader: FinanceKitHTTPBatchUploader.live(
          gate: gate,
          credential: credential,
          canUpload: {
            !revocationStore.isRevoked && (try? credentialStore.credential(for: publisherID)) == credential
          }
        ),
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

  func disconnect() async throws {
    // Attempt each local cleanup even if revocation, decoding, or remote deletion fails.
    var failure: (any Error)?
    do { try blockBackgroundDelivery() } catch { failure = error }
    let environment = try makeEnvironment()
    let lock = try FinanceKitProcessLock(url: environment.lockURL).acquire()
    defer { _ = lock }
    let stateStore = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    var connectionID: UUID?
    do { connectionID = try await stateStore.load().configuration?.connectionID }
    catch { failure = error }
    do { try makeCredentialStore(environment.keychainAccessGroup).removeAllCredentials() }
    catch { failure = error }
    do { try await stateStore.clear() }
    catch { failure = error }
    if let connectionID {
      do { try await remoteDisconnect(connectionID) }
      catch { if failure == nil { failure = error } }
    }
    if let failure { throw failure }
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
