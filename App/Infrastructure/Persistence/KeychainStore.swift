import Foundation
import Security

enum KeychainStore {
  private static let service = "am.sure.insights"

  @discardableResult
  static func save(_ value: String, account: String, scope: Scope = .deviceOnly) -> Bool {
    guard !value.isEmpty else {
      return remove(account, scope: scope)
    }

    let encoded = Data(value.utf8)
    let status = SecItemUpdate(
      query(account: account, scope: scope) as CFDictionary,
      [kSecValueData as String: encoded] as CFDictionary
    )
    if status == errSecSuccess {
      return true
    }
    guard status == errSecItemNotFound else {
      return false
    }

    var attributes = query(account: account, scope: scope)
    attributes[kSecValueData as String] = encoded
    attributes[kSecAttrAccessible as String] = scope.accessibility
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  static func read(account: String, scope: Scope = .deviceOnly) -> String? {
    var lookup = query(account: account, scope: scope)
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func contains(account: String, scope: Scope = .deviceOnly) -> Bool {
    read(account: account, scope: scope) != nil
  }

  @discardableResult
  static func remove(_ account: String, scope: Scope = .deviceOnly) -> Bool {
    let status = SecItemDelete(query(account: account, scope: scope) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  private static func query(account: String, scope: Scope) -> [String: Any] {
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
