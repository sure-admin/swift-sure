import Foundation

enum NotificationStateStoreError: LocalizedError, Equatable {
  case invalidStoredState
  case persistenceFailed

  var errorDescription: String? {
    switch self {
    case .invalidStoredState:
      "The stored notification subscription is invalid."
    case .persistenceFailed:
      "The notification subscription could not be saved securely."
    }
  }
}
