import Foundation

struct KeychainCredentialRepository: CredentialRepository {
  private var storage: any SecretValueStoring
  private var legacyServerURL: String?

  init(
    storage: any SecretValueStoring = KeychainSecretValueStore(),
    legacyServerURL: String? = nil
  ) {
    self.storage = storage
    self.legacyServerURL = legacyServerURL
  }

  func loadCredentials() throws -> StoredCredentialSnapshot {
    if let stored = storage.value(for: StorageKey.activeSession, scope: .deviceOnly) {
      let session: StoredAuthenticatedSession = try decode(stored)
      maintainMigratedStorage(for: session)
      return StoredCredentialSnapshot(session: session)
    }

    if let stored = storage.value(for: StorageKey.apiKeyBackup, scope: .iCloud) {
      let session: StoredAPIKeySession = try decode(stored)
      return try migrate(.apiKey(session))
    }

    if let stored = storage.value(for: StorageKey.oauthSession, scope: .deviceOnly) {
      let session: StoredOAuthSession = try decode(stored)
      return try migrate(.oauth(session))
    }
    if let stored = storage.value(for: StorageKey.apiKeySession, scope: .iCloud) {
      let session: StoredAPIKeySession = try decode(stored)
      return try migrate(.apiKey(session))
    }
    if let stored = storage.value(for: StorageKey.oauthCredentials, scope: .deviceOnly) {
      let credentials: StoredOAuthCredentials = try decode(stored)
      return try migrate(.oauth(migratedOAuthSession(credentials)))
    }
    if let stored = storage.value(for: StorageKey.apiKeyCredentials, scope: .iCloud) {
      let credentials: LegacyAPIKeyCredentials = try decode(stored)
      return try migrate(.apiKey(migratedAPIKeySession(credentials)))
    }

    let accessToken = storage.value(for: LegacyStorageKey.oauthAccessToken, scope: .deviceOnly)
    let refreshToken = storage.value(for: LegacyStorageKey.oauthRefreshToken, scope: .deviceOnly)
    if accessToken != nil || refreshToken != nil {
      guard let accessToken, !accessToken.isEmpty else {
        throw CredentialRepositoryError.invalidStoredCredentials
      }
      let credentials: StoredOAuthCredentials
      do {
        credentials = try StoredOAuthCredentials(
          accessToken: accessToken,
          refreshToken: refreshToken
        )
      } catch {
        throw CredentialRepositoryError.invalidStoredCredentials
      }
      return try migrate(.oauth(migratedOAuthSession(credentials)))
    }

    if let apiKey = storage.value(for: LegacyStorageKey.apiKey, scope: .iCloud) {
      guard !apiKey.isEmpty else {
        throw CredentialRepositoryError.invalidStoredCredentials
      }
      let credentials = LegacyAPIKeyCredentials(
        apiKey: apiKey,
        isVerified: storage.value(
          for: LegacyStorageKey.verifiedAPIKey,
          scope: .iCloud
        ) == "true"
      )
      return try migrate(.apiKey(migratedAPIKeySession(credentials)))
    }

    return StoredCredentialSnapshot(session: nil)
  }

  func replaceSession(_ session: StoredAuthenticatedSession?) throws {
    guard let session else {
      try removeAllCredentials()
      return
    }

    try store(session, for: StorageKey.activeSession, scope: .deviceOnly)
    maintainMigratedStorage(for: session)
  }

  private func migrate(
    _ session: StoredAuthenticatedSession
  ) throws -> StoredCredentialSnapshot {
    try store(session, for: StorageKey.activeSession, scope: .deviceOnly)
    maintainMigratedStorage(for: session)
    return StoredCredentialSnapshot(session: session)
  }

  private func migratedOAuthSession(
    _ credentials: StoredOAuthCredentials
  ) throws -> StoredOAuthSession {
    do {
      return try StoredOAuthSession(
        serverURL: legacyBaseURL(),
        credentials: credentials,
        isVerified: false
      )
    } catch {
      throw CredentialRepositoryError.invalidStoredCredentials
    }
  }

  private func migratedAPIKeySession(
    _ credentials: LegacyAPIKeyCredentials
  ) throws -> StoredAPIKeySession {
    do {
      return try StoredAPIKeySession(
        serverURL: legacyBaseURL(),
        apiKey: credentials.apiKey,
        isVerified: false
      )
    } catch {
      throw CredentialRepositoryError.invalidStoredCredentials
    }
  }

  private func legacyBaseURL() throws -> URL {
    guard let legacyServerURL,
          let url = URL(string: legacyServerURL.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      throw CredentialRepositoryError.invalidStoredCredentials
    }
    return url
  }

  private func store<Value: Encodable>(
    _ value: Value,
    for key: String,
    scope: SecretValueScope
  ) throws {
    do {
      let data = try JSONEncoder().encode(value)
      guard let encoded = String(data: data, encoding: .utf8) else {
        throw CredentialRepositoryError.persistenceFailed
      }
      try storage.setValue(encoded, for: key, scope: scope)
    } catch let error as CredentialRepositoryError {
      throw error
    } catch {
      throw CredentialRepositoryError.persistenceFailed
    }
  }

  private func decode<Value: Decodable>(_ stored: String) throws -> Value {
    do {
      return try JSONDecoder().decode(Value.self, from: Data(stored.utf8))
    } catch {
      throw CredentialRepositoryError.invalidStoredCredentials
    }
  }

  private func removeAllCredentials() throws {
    var didFail = false
    for value in allStoredValues {
      do {
        try storage.removeValue(for: value.key, scope: value.scope)
      } catch {
        didFail = true
      }
    }
    if didFail {
      throw CredentialRepositoryError.persistenceFailed
    }
  }

  private func maintainMigratedStorage(for session: StoredAuthenticatedSession) {
    var hasAPIKeyBackup = storage.value(
      for: StorageKey.apiKeyBackup,
      scope: .iCloud
    ) != nil
    if case .apiKey(let apiKeySession) = session {
      do {
        try store(apiKeySession, for: StorageKey.apiKeyBackup, scope: .iCloud)
        hasAPIKeyBackup = true
      } catch {
        // The device-local active session is already committed. A failed sync
        // mirror must not make the selected session appear to have rolled back.
      }
    }

    for value in supersededDeviceValues {
      try? storage.removeValue(for: value.key, scope: value.scope)
    }
    if hasAPIKeyBackup {
      for value in supersededAPIKeyValues {
        try? storage.removeValue(for: value.key, scope: value.scope)
      }
    }
  }

  private var allStoredValues: [(key: String, scope: SecretValueScope)] {
    [
      (StorageKey.activeSession, .deviceOnly),
      (StorageKey.apiKeyBackup, .iCloud),
      (StorageKey.oauthSession, .deviceOnly),
      (StorageKey.apiKeySession, .iCloud),
      (StorageKey.oauthCredentials, .deviceOnly),
      (StorageKey.apiKeyCredentials, .iCloud),
      (LegacyStorageKey.oauthAccessToken, .deviceOnly),
      (LegacyStorageKey.oauthRefreshToken, .deviceOnly),
      (LegacyStorageKey.apiKey, .iCloud),
      (LegacyStorageKey.verifiedAPIKey, .iCloud)
    ]
  }

  private var supersededDeviceValues: [(key: String, scope: SecretValueScope)] {
    [
      (StorageKey.oauthSession, .deviceOnly),
      (StorageKey.oauthCredentials, .deviceOnly),
      (LegacyStorageKey.oauthAccessToken, .deviceOnly),
      (LegacyStorageKey.oauthRefreshToken, .deviceOnly)
    ]
  }

  private var supersededAPIKeyValues: [(key: String, scope: SecretValueScope)] {
    [
      (StorageKey.apiKeySession, .iCloud),
      (StorageKey.apiKeyCredentials, .iCloud),
      (LegacyStorageKey.apiKey, .iCloud),
      (LegacyStorageKey.verifiedAPIKey, .iCloud)
    ]
  }

  private enum StorageKey {
    static let activeSession = "sure.authenticatedSession.v3"
    static let apiKeyBackup = "sure.apiKeySessionBackup.v3"
    static let oauthSession = "sure.oauthSession.v2"
    static let apiKeySession = "sure.apiKeySession.v2"
    static let oauthCredentials = "sure.oauthCredentials.v1"
    static let apiKeyCredentials = "sure.apiKeyCredentials.v1"
  }

  private enum LegacyStorageKey {
    static let oauthAccessToken = "oauthAccessToken"
    static let oauthRefreshToken = "oauthRefreshToken"
    static let apiKey = "apiKey"
    static let verifiedAPIKey = "verifiedAPIKey"
  }
}

private struct LegacyAPIKeyCredentials: Codable {
  var apiKey: String
  var isVerified: Bool
}
