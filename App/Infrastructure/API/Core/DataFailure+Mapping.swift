import Foundation

extension DataFailure {
  init(_ error: Error) {
    if let failure = error as? DataFailure { self = failure; return }
    if error is CancellationError || (error as? URLError)?.code == .cancelled { self = .cancelled; return }
    if error is BackendAccessError { self = .subscription; return }
    if error is URLError { self = .offline; return }
    guard let api = error as? SureAPIError else {
      self = error is DecodingError ? .malformed : .unknown
      return
    }
    self = switch api {
    case .unauthorized: .authentication
    case .forbidden: .authorization
    case .featureUnavailable, .previewFeatureUnavailable, .notFound: .unavailable
    case .validation, .invalidURL: .validation
    case .decoding, .invalidResponse: .malformed
    case .transport: .offline
    case .rateLimited: .rateLimited
    case .server, .backend, .responseTimeout, .unexpectedStatus: .server
    case .encoding: .unknown
    }
  }
}
