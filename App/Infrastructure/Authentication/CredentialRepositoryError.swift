import Foundation

enum CredentialRepositoryError: LocalizedError, Equatable {
  case invalidStoredCredentials
  case persistenceFailed

  var errorDescription: String? {
    switch self {
    case .invalidStoredCredentials:
      "The saved Sure credentials are invalid. Sign in again."
    case .persistenceFailed:
      "The Sure credentials couldn’t be saved securely."
    }
  }
}
