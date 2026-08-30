import Foundation

enum MobileSSOError: Equatable, LocalizedError {
  case invalidCallback
  case invalidProviderResponse
  case providerUnavailable
  case couldNotStart
  case signInFailed
  case server(Int)
  case transport

  var errorDescription: String? {
    switch self {
    case .invalidCallback: "Sure returned an invalid sign-in response."
    case .invalidProviderResponse: "The sign-in provider returned an invalid response to Sure."
    case .providerUnavailable: "This sign-in provider isn’t available on this Sure server."
    case .couldNotStart: "The secure sign-in window couldn’t open."
    case .signInFailed: "Sure’s server couldn’t complete provider sign-in. Check its SSO logs."
    case .server(let statusCode): "Sure returned sign-in error \(statusCode)."
    case .transport: "The app could not reach the Sure server."
    }
  }
}
