import Foundation

struct FinanceKitBackgroundSyncRunner: Sendable {
  var makeEnvironment: @Sendable () throws -> FinanceKitPublisherEnvironment = {
    try FinanceKitPublisherEnvironment.live()
  }
  var entitlementReader = FinanceKitBackgroundEntitlementReader()

  func run(changedTypes: Set<FinanceKitBackgroundDataType>) async {
    do {
      let environment = try makeEnvironment()
      let revocationStore = FinanceKitPublisherRevocationStore(
        fileURL: environment.revocationURL
      )
      guard !revocationStore.isRevoked else { return }
      let stateStore = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
      let state = try await stateStore.load()
      guard let configuration = state.configuration else { return }

      let credentialStore = FinanceKitPublisherCredentialStore(
        accessGroup: environment.keychainAccessGroup
      )
      guard let credential = try credentialStore.credential(
        for: configuration.publisherID
      ) else { return }

      let gate = BackendAccessGate()
      gate.update(expiration: await entitlementReader.expiration())
      try gate.check()
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
      _ = try await engine.synchronize(changedTypes: changedTypes)
    } catch {
      // The extension never logs credentials, payloads, account identifiers, or financial data.
      // Unacknowledged state remains in the protected outbox for the next delivery.
    }
  }
}
