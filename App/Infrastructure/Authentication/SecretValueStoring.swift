import Foundation

protocol SecretValueStoring: Sendable {
  func value(for key: String, scope: SecretValueScope) -> String?
  func setValue(_ value: String, for key: String, scope: SecretValueScope) throws
  func removeValue(for key: String, scope: SecretValueScope) throws
}

enum SecretValueScope: Sendable {
  case deviceOnly
  case iCloud
}

struct KeychainSecretValueStore: SecretValueStoring {
  func value(for key: String, scope: SecretValueScope) -> String? {
    KeychainStore.read(account: key, scope: scope.keychainScope)
  }

  func setValue(_ value: String, for key: String, scope: SecretValueScope) throws {
    guard KeychainStore.save(value, account: key, scope: scope.keychainScope) else {
      throw SecretValueStorageError.persistenceFailed
    }
  }

  func removeValue(for key: String, scope: SecretValueScope) throws {
    guard KeychainStore.remove(key, scope: scope.keychainScope) else {
      throw SecretValueStorageError.persistenceFailed
    }
  }
}

private extension SecretValueScope {
  var keychainScope: KeychainStore.Scope {
    switch self {
    case .deviceOnly: .deviceOnly
    case .iCloud: .iCloud
    }
  }
}

private enum SecretValueStorageError: Error {
  case persistenceFailed
}
