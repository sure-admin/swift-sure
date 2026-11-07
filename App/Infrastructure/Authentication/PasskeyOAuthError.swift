import Foundation

enum PasskeyOAuthError: Equatable, LocalizedError {
  case invalidServerURL
  case invalidResponse
  case couldNotStart
  case randomGenerationFailed
  case missingClientRegistration
  case authorizationRejected
  case rejected(OAuthOperation, OAuthFailure?, Int)
  case transport

  var errorDescription: String? {
    switch self {
    case .invalidServerURL: "Enter a valid HTTPS Sure server URL."
    case .invalidResponse: "Sure returned an invalid sign-in response."
    case .couldNotStart: "The secure sign-in window couldn’t open."
    case .randomGenerationFailed: "A secure sign-in request couldn’t be created."
    case .missingClientRegistration: "This app is not registered with the Sure server."
    case .authorizationRejected: "Sure did not authorize this sign-in request."
    case .rejected(let operation, let failure, let status):
      switch failure {
      case .invalidClient, .unauthorizedClient:
        "Sure no longer recognizes this app’s sign-in registration."
      case .invalidGrant:
        "Sure rejected the sign-in code or refresh token. Start sign-in again."
      case .invalidClientMetadata:
        "Sure rejected the app’s sign-in registration settings."
      case .invalidScope:
        "Sure rejected the permissions requested by this app."
      case .invalidRequest:
        "Sure rejected the \(operation.label) request as invalid (HTTP \(status))."
      case .unsupportedGrantType:
        "Sure does not support this app’s OAuth sign-in method."
      case nil:
        "Sure rejected the \(operation.label) request (HTTP \(status))."
      }
    case .transport: "The app could not reach the Sure server."
    }
  }
}

enum OAuthOperation: Equatable, Sendable {
  case registration, tokenExchange, revocation

  var label: String {
    switch self {
    case .registration: "app registration"
    case .tokenExchange: "sign-in token"
    case .revocation: "sign-out"
    }
  }
}

enum OAuthFailure: String, Equatable, Sendable {
  case invalidClient = "invalid_client"
  case unauthorizedClient = "unauthorized_client"
  case invalidGrant = "invalid_grant"
  case invalidClientMetadata = "invalid_client_metadata"
  case invalidScope = "invalid_scope"
  case invalidRequest = "invalid_request"
  case unsupportedGrantType = "unsupported_grant_type"
}
