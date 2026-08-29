import Foundation
import Testing
@testable import Sure

@Suite("Keychain credential repository")
struct KeychainCredentialRepositoryTests {
  @Test("Legacy OAuth is preserved but remains unverified until explicit sign-in")
  func migratesLegacyOAuthFailClosed() throws {
    let storage = InMemorySecretValueStore()
    storage.seed("old-access", for: "oauthAccessToken", scope: .deviceOnly)
    storage.seed("old-refresh", for: "oauthRefreshToken", scope: .deviceOnly)
    let repository = KeychainCredentialRepository(
      storage: storage,
      legacyServerURL: "https://SURE.example:443/"
    )

    let credentials = try repository.loadCredentials()

    #expect(credentials.oauthSession?.serverURL.absoluteString == "https://sure.example")
    #expect(credentials.oauthCredentials?.accessToken == "old-access")
    #expect(credentials.oauthCredentials?.refreshToken == "old-refresh")
    #expect(credentials.oauthSession?.isVerified == false)
    #expect(storage.value(for: "sure.authenticatedSession.v3", scope: .deviceOnly) != nil)
    #expect(storage.value(for: "oauthAccessToken", scope: .deviceOnly) == nil)
    #expect(storage.value(for: "oauthRefreshToken", scope: .deviceOnly) == nil)
    #expect(try repository.loadCredentials() == credentials)
  }

  @Test("Legacy synchronized API keys require verification and gain a bound backup")
  func migratesLegacyAPIKeyFailClosed() throws {
    let storage = InMemorySecretValueStore()
    storage.seed("old-api-key", for: "apiKey", scope: .iCloud)
    storage.seed("true", for: "verifiedAPIKey", scope: .iCloud)
    let repository = KeychainCredentialRepository(
      storage: storage,
      legacyServerURL: "https://sure.example"
    )

    let credentials = try repository.loadCredentials()

    #expect(credentials.apiKey == "old-api-key")
    #expect(credentials.apiKeySession?.serverURL.absoluteString == "https://sure.example")
    #expect(credentials.isAPIKeyVerified == false)
    #expect(storage.value(for: "sure.apiKeySessionBackup.v3", scope: .iCloud) != nil)
    #expect(storage.value(for: "apiKey", scope: .iCloud) == nil)
    #expect(storage.value(for: "verifiedAPIKey", scope: .iCloud) == nil)
  }

  @Test("A host-bound API-key backup safely hydrates a new device")
  func apiKeyBackupHydration() throws {
    let sharedStorage = InMemorySecretValueStore()
    let firstRepository = KeychainCredentialRepository(storage: sharedStorage)
    let session = try StoredAPIKeySession(
      serverURL: #require(URL(string: "https://sure.example")),
      apiKey: "verified-key",
      isVerified: true
    )
    try firstRepository.replaceSession(.apiKey(session))
    sharedStorage.removeFromDevice("sure.authenticatedSession.v3")

    let hydrated = try KeychainCredentialRepository(storage: sharedStorage).loadCredentials()

    #expect(hydrated.apiKeySession == session)
    #expect(hydrated.isAPIKeyVerified)
  }

  @Test("A failed active-session replacement preserves the previous session")
  func failedAtomicReplacement() throws {
    let storage = InMemorySecretValueStore()
    let repository = KeychainCredentialRepository(storage: storage)
    let previous = try oauthSession(access: "previous-access")
    try repository.replaceSession(.oauth(previous))
    storage.failNextWrite()

    do {
      try repository.replaceSession(.oauth(oauthSession(access: "replacement-access")))
      #expect(Bool(false))
    } catch let error as CredentialRepositoryError {
      #expect(error == .persistenceFailed)
      #expect(!error.localizedDescription.contains("replacement-access"))
    }

    #expect(try repository.loadCredentials().oauthSession == previous)
  }

  @Test("A failed migration leaves legacy values available for retry")
  func failedMigration() throws {
    let storage = InMemorySecretValueStore()
    storage.seed("legacy-access", for: "oauthAccessToken", scope: .deviceOnly)
    storage.seed("legacy-refresh", for: "oauthRefreshToken", scope: .deviceOnly)
    storage.failNextWrite()
    let repository = KeychainCredentialRepository(
      storage: storage,
      legacyServerURL: "https://sure.example"
    )

    do {
      _ = try repository.loadCredentials()
      #expect(Bool(false))
    } catch let error as CredentialRepositoryError {
      #expect(error == .persistenceFailed)
    }

    #expect(storage.value(for: "oauthAccessToken", scope: .deviceOnly) == "legacy-access")
    #expect(storage.value(for: "oauthRefreshToken", scope: .deviceOnly) == "legacy-refresh")
    #expect(storage.value(for: "sure.authenticatedSession.v3", scope: .deviceOnly) == nil)
  }

  @Test("An unbound or incomplete legacy OAuth value is rejected without deletion")
  func invalidLegacyOAuthCredentials() {
    let missingServerStorage = InMemorySecretValueStore()
    missingServerStorage.seed("legacy-access", for: "oauthAccessToken", scope: .deviceOnly)
    expectInvalidCredentials(
      KeychainCredentialRepository(storage: missingServerStorage)
    )
    #expect(
      missingServerStorage.value(for: "oauthAccessToken", scope: .deviceOnly)
        == "legacy-access"
    )

    let incompleteStorage = InMemorySecretValueStore()
    incompleteStorage.seed("orphan-refresh", for: "oauthRefreshToken", scope: .deviceOnly)
    expectInvalidCredentials(
      KeychainCredentialRepository(
        storage: incompleteStorage,
        legacyServerURL: "https://sure.example"
      )
    )
    #expect(
      incompleteStorage.value(for: "oauthRefreshToken", scope: .deviceOnly)
        == "orphan-refresh"
    )
  }

  @Test("Clear attempts every credential generation and reports removal failure")
  func clearAllCredentials() throws {
    let storage = InMemorySecretValueStore()
    let repository = KeychainCredentialRepository(storage: storage)
    try repository.replaceSession(.oauth(oauthSession(access: "active-access")))
    storage.seed("legacy-api", for: "apiKey", scope: .iCloud)
    storage.failRemoval(for: "sure.authenticatedSession.v3", scope: .deviceOnly)

    do {
      try repository.replaceSession(nil)
      #expect(Bool(false))
    } catch let error as CredentialRepositoryError {
      #expect(error == .persistenceFailed)
    }

    #expect(storage.value(for: "sure.authenticatedSession.v3", scope: .deviceOnly) != nil)
    #expect(storage.value(for: "apiKey", scope: .iCloud) == nil)
  }

  private func oauthSession(access: String) throws -> StoredOAuthSession {
    try StoredOAuthSession(
      serverURL: #require(URL(string: "https://sure.example")),
      credentials: StoredOAuthCredentials(accessToken: access, refreshToken: "refresh"),
      isVerified: true
    )
  }

  private func expectInvalidCredentials(_ repository: KeychainCredentialRepository) {
    do {
      _ = try repository.loadCredentials()
      #expect(Bool(false))
    } catch let error as CredentialRepositoryError {
      #expect(error == .invalidStoredCredentials)
    } catch {
      #expect(Bool(false))
    }
  }
}

private final class InMemorySecretValueStore: SecretValueStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]
  private var shouldFailNextWrite = false
  private var removalFailures: Set<String> = []

  func value(for key: String, scope: SecretValueScope) -> String? {
    lock.withLock { values[storageKey(key, scope: scope)] }
  }

  func setValue(_ value: String, for key: String, scope: SecretValueScope) throws {
    try lock.withLock {
      if shouldFailNextWrite {
        shouldFailNextWrite = false
        throw InMemorySecretValueStoreError.expectedFailure
      }
      values[storageKey(key, scope: scope)] = value
    }
  }

  func removeValue(for key: String, scope: SecretValueScope) throws {
    try lock.withLock {
      let storedKey = storageKey(key, scope: scope)
      if removalFailures.contains(storedKey) {
        throw InMemorySecretValueStoreError.expectedFailure
      }
      values[storedKey] = nil
    }
  }

  func seed(_ value: String, for key: String, scope: SecretValueScope) {
    lock.withLock { values[storageKey(key, scope: scope)] = value }
  }

  func failNextWrite() {
    lock.withLock { shouldFailNextWrite = true }
  }

  func failRemoval(for key: String, scope: SecretValueScope) {
    _ = lock.withLock { removalFailures.insert(storageKey(key, scope: scope)) }
  }

  func removeFromDevice(_ key: String) {
    lock.withLock { values[storageKey(key, scope: .deviceOnly)] = nil }
  }

  private func storageKey(_ key: String, scope: SecretValueScope) -> String {
    let scopeName = switch scope {
    case .deviceOnly: "device"
    case .iCloud: "icloud"
    }
    return "\(scopeName):\(key)"
  }
}

private enum InMemorySecretValueStoreError: Error {
  case expectedFailure
}
