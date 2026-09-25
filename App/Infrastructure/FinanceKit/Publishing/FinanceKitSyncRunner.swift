import Foundation

/// Builds the live publishing stack and runs one synchronisation pass.
///
/// The foreground trigger needs the outcome and the failure; the background
/// extension must never log either. `run` serves the first, `runQuietly` the
/// second, so both paths share one assembly of the stack.
struct FinanceKitSyncRunner: Sendable {
  var makeEnvironment: @Sendable () throws -> FinanceKitPublisherEnvironment = {
    try FinanceKitPublisherEnvironment.live()
  }
  var entitlementReader = FinanceKitBackgroundEntitlementReader()

  /// Passing an empty `changedTypes` collects everything since the checkpoint.
  @discardableResult
  func run(
    changedTypes: Set<FinanceKitBackgroundDataType>
  ) async throws -> FinanceKitSyncOutcome {
    let environment = try makeEnvironment()
    let revocationStore = FinanceKitPublisherRevocationStore(
      fileURL: environment.revocationURL
    )
    guard !revocationStore.isRevoked else { throw FinanceKitBatchUploadError.publisherRevoked }
    let stateStore = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    let credentialStore = FinanceKitPublisherCredentialStore(
      accessGroup: environment.keychainAccessGroup
    )

    let gate = BackendAccessGate()
    gate.update(expiration: await entitlementReader.expiration())
    let engine = FinanceKitSyncEngine(
      stateStore: stateStore,
      collector: FinanceKitHistoryChangeCollector(),
      makeUploader: { configuration in
        try gate.check()
        guard !revocationStore.isRevoked else { throw FinanceKitBatchUploadError.publisherRevoked }
        guard let credential = try credentialStore.credential(for: configuration.publisherID) else {
          throw FinanceKitSyncError.invalidState
        }
        return FinanceKitHTTPBatchUploader.live(
          gate: gate,
          credential: credential,
          canUpload: {
            !revocationStore.isRevoked &&
              (try? credentialStore.credential(for: configuration.publisherID)) == credential
          }
        )
      },
      processLock: FinanceKitProcessLock(url: environment.lockURL)
    )
    return try await engine.synchronize(changedTypes: changedTypes)
  }

  func runQuietly(changedTypes: Set<FinanceKitBackgroundDataType>) async {
    do {
      _ = try await run(changedTypes: changedTypes)
    } catch {
      // The extension never logs credentials, payloads, account identifiers, or financial data.
      // Unacknowledged state remains in the protected outbox for the next delivery.
    }
  }
}
