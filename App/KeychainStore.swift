import Foundation
import Security

enum KeychainStore {
  private static let service = "am.sure.insights"
  private static let legacyService = "am.sure.native"

  @discardableResult
  static func save(_ value: String, account: String, scope: Scope = .deviceOnly) -> Bool {
    guard !value.isEmpty else {
      delete(account: account, service: service, scope: scope)
      if scope == .iCloud {
        delete(account: account, service: service, scope: .deviceOnly)
        delete(account: account, service: legacyService, scope: .deviceOnly)
      }
      return false
    }

    let encoded = Data(value.utf8)
    let status = SecItemUpdate(
      query(account: account, service: service, scope: scope) as CFDictionary,
      [kSecValueData as String: encoded] as CFDictionary
    )
    if status == errSecSuccess {
      return true
    }
    guard status == errSecItemNotFound else {
      return false
    }

    var attributes = query(account: account, service: service, scope: scope)
    attributes[kSecValueData as String] = encoded
    attributes[kSecAttrAccessible as String] = scope.accessibility
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  static func read(account: String, scope: Scope = .deviceOnly) -> String? {
    if let value = read(account: account, service: service, scope: scope) {
      return value
    }

    let migrationSources: [(String, Scope)] = scope == .iCloud
      ? [(service, .deviceOnly), (legacyService, .deviceOnly)]
      : [(legacyService, .deviceOnly)]
    for (sourceService, sourceScope) in migrationSources {
      guard let value = read(account: account, service: sourceService, scope: sourceScope) else {
        continue
      }
      if save(value, account: account, scope: scope) {
        delete(account: account, service: sourceService, scope: sourceScope)
      }
      return value
    }
    return nil
  }

  static func contains(account: String, scope: Scope = .deviceOnly) -> Bool {
    read(account: account, service: service, scope: scope) != nil
  }

  private static func read(account: String, service: String, scope: Scope) -> String? {
    var lookup = query(account: account, service: service, scope: scope)
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func delete(account: String, service: String, scope: Scope) {
    SecItemDelete(query(account: account, service: service, scope: scope) as CFDictionary)
  }

  private static func query(account: String, service: String, scope: Scope) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: scope.isSynchronizable
    ]
  }

  enum Scope: Equatable {
    case deviceOnly
    case iCloud

    var isSynchronizable: Bool {
      self == .iCloud
    }

    var accessibility: CFString {
      switch self {
      case .deviceOnly:
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      case .iCloud:
        kSecAttrAccessibleAfterFirstUnlock
      }
    }
  }
}
