import Foundation

enum SureAPIError: Error, Equatable, LocalizedError {
  case invalidURL
  case invalidResponse
  case unauthorized
  case forbidden
  case featureUnavailable
  case previewFeatureUnavailable
  case notFound
  case validation
  case encoding
  case decoding
  case transport
  case rateLimited
  case server(Int)
  case unexpectedStatus(Int)

  case backend
  case responseTimeout

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      "The Sure server URL is invalid."
    case .invalidResponse:
      "Sure returned an unexpected response."
    case .unauthorized:
      "Sure rejected the current credentials."
    case .forbidden:
      "The current credentials do not have access to this operation."
    case .featureUnavailable:
      "This feature is not enabled on the connected Sure instance."
    case .previewFeatureUnavailable:
      "This preview feature is not enabled on the connected Sure instance."
    case .notFound:
      "The requested Sure record could not be found."
    case .validation:
      "Sure rejected the request because it was invalid."
    case .encoding:
      "The request could not be prepared."
    case .decoding:
      "Sure returned data in an unexpected format."
    case .transport:
      "The app could not reach the Sure server."
    case .rateLimited:
      "Sure is receiving too many requests. Try again in a moment."
    case .server(let statusCode):
      "Sure returned server error \(statusCode)."
    case .unexpectedStatus(let statusCode):
      "Sure returned unexpected HTTP status \(statusCode)."
    case .backend:
      "Sure could not generate a response."
    case .responseTimeout:
      "Sure is still working on that response. Try again in a moment."
    }
  }
}
