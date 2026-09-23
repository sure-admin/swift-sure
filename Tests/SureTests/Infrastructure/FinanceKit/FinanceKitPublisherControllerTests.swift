import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit publisher lifecycle")
struct FinanceKitPublisherControllerTests {
  @Test("Remote disconnect failure still deletes credentials, checkpoint and pending state")
  func remoteFailureClearsLocalData() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    let credentials = PublisherCredentials()
    let store = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    var state = FinanceKitPublisherState.empty
    state.configuration = try configuration()
    state.checkpoint = Data("private-checkpoint".utf8)
    try await store.save(state)
    let controller = FinanceKitPublisherController(gate: BackendAccessGate(), makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials }, remoteDisconnect: { _ in
        #expect(try await store.load() == .empty)
        #expect(credentials.isEmpty)
        throw URLError(.notConnectedToInternet)
      })
    #expect(await controller.configuredConnectionID() == state.configuration?.connectionID)
    await #expect(throws: URLError.self) { try await controller.disconnect() }
    #expect(credentials.isEmpty)
    #expect(try await store.load() == .empty)
    #expect(await controller.configuredConnectionID() == nil)
  }

  @Test("An unreadable state does not prevent deletion of local financial records")
  func corruptStateIsDeleted() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: environment.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("invalid-json".utf8).write(to: environment.stateURL)
    let credentials = PublisherCredentials()
    let controller = FinanceKitPublisherController(gate: BackendAccessGate(), makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials })
    await #expect(throws: FinanceKitSyncError.invalidState) { try await controller.disconnect() }
    #expect(credentials.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: environment.stateURL.path))
  }

  @Test("A failed marker write synchronously invalidates the shared credential")
  func markerFailureInvalidatesCredential() throws {
    var environment = environment()
    let folder = environment.stateURL.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let obstruction = folder.appendingPathComponent("not-a-directory")
    try Data().write(to: obstruction)
    environment.revocationURL = obstruction.appendingPathComponent("revoked")
    let fixedEnvironment = environment
    let credentials = PublisherCredentials()
    let controller = FinanceKitPublisherController(gate: BackendAccessGate(), makeEnvironment: { fixedEnvironment },
      makeCredentialStore: { _ in credentials })
    try controller.blockBackgroundDelivery()
    #expect(credentials.isEmpty)
    #expect(!FinanceKitPublisherRevocationStore(fileURL: environment.revocationURL).isRevoked)
  }

  @Test("Revoked configuration never becomes an active connection after relaunch")
  func revokedConfigurationIsHidden() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    var state = FinanceKitPublisherState.empty
    state.configuration = try configuration()
    state.requiresRepair = true
    try await FinanceKitPublisherStateFileStore(fileURL: environment.stateURL).save(state)
    let credentials = PublisherCredentials()
    let controller = FinanceKitPublisherController(gate: BackendAccessGate(), makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials })
    #expect(await controller.requiresRepair())
    try controller.blockBackgroundDelivery()
    #expect(await controller.configuredConnectionID() == nil)
  }

  private func environment() -> FinanceKitPublisherEnvironment {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return .init(stateURL: folder.appendingPathComponent("state.json"), lockURL: folder.appendingPathComponent("lock"),
      revocationURL: folder.appendingPathComponent("revoked"), keychainAccessGroup: "test-only")
  }

  private func configuration() throws -> FinanceKitPublisherConfiguration {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return try #require(formatter.date(from: value))
    }
    return try decoder.decode(FinanceKitActivation.self, from: APIFixture.data(named: "financekit-activation")).configuration()
  }
}

private final class PublisherCredentials: FinanceKitPublisherCredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var value: String? = "test-only"
  var isEmpty: Bool { lock.withLock { value == nil } }
  func credential(for publisherID: UUID) throws -> String? { lock.withLock { value } }
  func saveCredential(_ credential: String, for publisherID: UUID) throws { lock.withLock { value = credential } }
  func removeCredential(for publisherID: UUID) throws { try removeAllCredentials() }
  func removeAllCredentials() throws { lock.withLock { value = nil } }
}
