import Foundation
import Security

enum KeychainStore {
  private static let service = "am.sure.insights"
  private static let legacyService = "am.sure.native"

  @discardableResult
  static func save(_ value: String, account: String) -> Bool {
    guard !value.isEmpty else {
      delete(account: account)
      return false
    }

    let encoded = Data(value.utf8)
    let status = SecItemUpdate(
      query(account: account, service: service) as CFDictionary,
      [kSecValueData as String: encoded] as CFDictionary
    )
    if status == errSecSuccess {
      return true
    }
    guard status == errSecItemNotFound else {
      return false
    }

    var attributes = query(account: account, service: service)
    attributes[kSecValueData as String] = encoded
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  static func read(account: String) -> String? {
    if let value = read(account: account, service: service) {
      return value
    }
    guard let legacyValue = read(account: account, service: legacyService) else {
      return nil
    }
    if save(legacyValue, account: account) {
      SecItemDelete(query(account: account, service: legacyService) as CFDictionary)
    }
    return legacyValue
  }

  private static func read(account: String, service: String) -> String? {
    var lookup = query(account: account, service: service)
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func delete(account: String) {
    SecItemDelete(query(account: account, service: service) as CFDictionary)
  }

  private static func query(account: String, service: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false
    ]
  }
}
