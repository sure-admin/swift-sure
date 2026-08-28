import Foundation

enum PasskeyOAuthError: LocalizedError {
  case invalidServerURL
  case invalidResponse
  case couldNotStart
  case randomGenerationFailed
  case backend(String)

  var errorDescription: String? {
    switch self {
    case .invalidServerURL: "Enter a valid HTTPS Sure server URL."
    case .invalidResponse: "Sure returned an invalid sign-in response."
    case .couldNotStart: "The secure sign-in window couldn’t open."
    case .randomGenerationFailed: "A secure sign-in request couldn’t be created."
    case .backend(let message): message
    }
  }
}
