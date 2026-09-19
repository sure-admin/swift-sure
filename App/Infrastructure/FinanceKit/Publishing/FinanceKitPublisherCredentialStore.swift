import Foundation
import Security

struct FinanceKitPublisherCredentialStore: FinanceKitPublisherCredentialStoring {
  var accessGroup: String
  private let service = "am.sure.insights.financekit.publisher"

  func credential(for publisherID: UUID) throws -> String? {
    var query = baseQuery(for: publisherID)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess,
          let data = result as? Data,
          let credential = String(data: data, encoding: .utf8),
          !credential.isEmpty else {
      throw FinanceKitPublisherCredentialError.readFailed
    }
    return credential
  }

  func saveCredential(_ credential: String, for publisherID: UUID) throws {
    guard !credential.isEmpty else { throw FinanceKitPublisherCredentialError.invalidCredential }
    let data = Data(credential.utf8)
    let status = SecItemUpdate(
      baseQuery(for: publisherID) as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else {
      throw FinanceKitPublisherCredentialError.writeFailed
    }
    var attributes = baseQuery(for: publisherID)
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
      throw FinanceKitPublisherCredentialError.writeFailed
    }
  }

  func removeCredential(for publisherID: UUID) throws {
    let status = SecItemDelete(baseQuery(for: publisherID) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw FinanceKitPublisherCredentialError.deleteFailed
    }
  }

  func removeAllCredentials() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccessGroup as String: accessGroup,
      kSecAttrSynchronizable as String: false
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw FinanceKitPublisherCredentialError.deleteFailed
    }
  }

  private func baseQuery(for publisherID: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: publisherID.uuidString.lowercased(),
      kSecAttrAccessGroup as String: accessGroup,
      kSecAttrSynchronizable as String: false
    ]
  }
}

enum FinanceKitPublisherCredentialError: Error {
  case invalidCredential
  case readFailed
  case writeFailed
  case deleteFailed
}
