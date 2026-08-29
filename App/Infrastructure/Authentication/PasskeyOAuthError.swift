import Foundation

enum PasskeyOAuthError: Equatable, LocalizedError {
  case invalidServerURL
  case invalidResponse
  case couldNotStart
  case randomGenerationFailed
  case missingClientRegistration
  case authorizationRejected
  case server(Int)
  case transport

  var errorDescription: String? {
    switch self {
    case .invalidServerURL: "Enter a valid HTTPS Sure server URL."
    case .invalidResponse: "Sure returned an invalid sign-in response."
    case .couldNotStart: "The secure sign-in window couldn’t open."
    case .randomGenerationFailed: "A secure sign-in request couldn’t be created."
    case .missingClientRegistration: "This app is not registered with the Sure server."
    case .authorizationRejected: "Sure did not authorize this sign-in request."
    case .server(let statusCode): "Sure returned OAuth error \(statusCode)."
    case .transport: "The app could not reach the Sure server."
    }
  }
}
