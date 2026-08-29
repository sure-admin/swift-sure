import Foundation

protocol CredentialRepository: Sendable {
  func loadCredentials() throws -> StoredCredentialSnapshot
  func replaceSession(_ session: StoredAuthenticatedSession?) throws
}
