import Foundation

protocol FinanceKitPublisherCredentialStoring: Sendable {
  func credential(for publisherID: UUID) throws -> String?
  func saveCredential(_ credential: String, for publisherID: UUID) throws
  func removeCredential(for publisherID: UUID) throws
  func removeAllCredentials() throws
}
