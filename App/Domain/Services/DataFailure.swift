import Foundation

/// Safe, actionable failure categories. Raw responses never become UI messages.
enum DataFailure: Error, Equatable, LocalizedError, Sendable {
  case cancelled, offline, authentication, authorization, subscription, unavailable
  case validation, malformed, rateLimited, server, persistence, cleanup, unknown

  var errorDescription: String? {
    switch self {
    case .cancelled: "The request was cancelled."
    case .offline: "Couldn’t reach Sure. Showing downloaded data when available."
    case .authentication: "Sign in again to refresh Sure data."
    case .authorization: "Your credentials don’t have access to this data."
    case .subscription: "An active subscription is required to refresh Sure data."
    case .unavailable: "This feature is unavailable on your Sure server."
    case .validation: "Sure rejected this request."
    case .malformed: "Sure returned data in an unexpected format."
    case .rateLimited: "Sure is busy. Try again shortly."
    case .server: "Sure couldn’t complete the request."
    case .persistence: "Downloaded data couldn’t be saved."
    case .cleanup: "Some downloaded data couldn’t be removed. Try signing out again."
    case .unknown: "The data couldn’t be loaded."
    }
  }

  var canRetry: Bool { [.offline, .rateLimited, .server, .persistence, .cleanup, .unknown].contains(self) }
  var allowsCachedRead: Bool { self == .offline || self == .subscription }
}
