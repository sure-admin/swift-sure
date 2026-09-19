import Foundation

#if os(iOS) && FINANCEKIT_ENABLED
import FinanceKit
#endif

actor FinanceKitPublisherController: FinanceKitPublisherLifecycleHandling {
  private var gate: BackendAccessGate
  private nonisolated let makeEnvironment: @Sendable () throws -> FinanceKitPublisherEnvironment
  private let remoteDisconnect: @Sendable (UUID) async throws -> Void

  init(
    gate: BackendAccessGate,
    makeEnvironment: @escaping @Sendable () throws -> FinanceKitPublisherEnvironment = {
      try FinanceKitPublisherEnvironment.live()
    },
    remoteDisconnect: @escaping @Sendable (UUID) async throws -> Void = { _ in }
  ) {
    self.gate = gate
    self.makeEnvironment = makeEnvironment
    self.remoteDisconnect = remoteDisconnect
  }

  func install(
    configuration: FinanceKitPublisherConfiguration,
    credential: String
  ) async throws {
    try gate.check()
    let environment = try makeEnvironment()
    let stateStore = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    let credentialStore = FinanceKitPublisherCredentialStore(
      accessGroup: environment.keychainAccessGroup
    )
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

  func resumeIfConfigured() async {
    guard gate.isAllowed else {
      await suspend()
      return
    }
    let environment: FinanceKitPublisherEnvironment
    let stateStore: FinanceKitPublisherStateFileStore
    let revocationStore: FinanceKitPublisherRevocationStore
    let credential: String
    do {
      environment = try makeEnvironment()
      revocationStore = FinanceKitPublisherRevocationStore(
        fileURL: environment.revocationURL
      )
      guard !revocationStore.isRevoked else { throw FinanceKitBatchUploadError.publisherRevoked }
      stateStore = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
      let state = try await stateStore.load()
      guard let configuredPublisher = state.configuration,
            let storedCredential = try FinanceKitPublisherCredentialStore(
        accessGroup: environment.keychainAccessGroup
      ).credential(for: configuredPublisher.publisherID) else { throw FinanceKitSyncError.invalidState }
      credential = storedCredential
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
          canUpload: { !revocationStore.isRevoked }
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

  nonisolated func blockBackgroundDelivery() {
    disableBackgroundDelivery()
    guard let environment = try? makeEnvironment() else { return }
    try? FinanceKitPublisherRevocationStore(fileURL: environment.revocationURL).revoke()
  }

  func disconnect() async throws {
    blockBackgroundDelivery()
    disableBackgroundDelivery()
    let environment = try makeEnvironment()
    let lock = try FinanceKitProcessLock(url: environment.lockURL).acquire()
    defer { _ = lock }
    let stateStore = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    let state = try await stateStore.load()
    if let connectionID = state.configuration?.connectionID { try await remoteDisconnect(connectionID) }
    let credentialStore = FinanceKitPublisherCredentialStore(accessGroup: environment.keychainAccessGroup)
    try credentialStore.removeAllCredentials()
    try await stateStore.clear()
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
