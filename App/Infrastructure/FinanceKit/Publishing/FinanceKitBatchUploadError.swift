/// A batch transport failure, paired with the server's protocol error code when
/// the response carried one.
///
/// The kind is the client's own classification of the status code; `code` is the
/// verbatim `{"error": "<code>"}` body from
/// `Api::V1::Financekit::BatchesController#protocol_error`. Keeping them apart
/// means a new server code reaches the caller without the client having to know
/// it in advance.
struct FinanceKitBatchUploadError: Error, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case authentication
    case authorization
    case conflict
    case invalidResponse
    case publisherRevoked
    case rateLimited(retryAfter: Int?)
    case rejected
    case server(Int)
    case tooLarge
  }

  var kind: Kind
  var code: String?

  init(kind: Kind, code: String? = nil) {
    self.kind = kind
    self.code = code
  }

  static let publisherUnauthorized = FinanceKitBatchUploadError(kind: .authentication, code: "publisher_unauthorized")
  static let authentication = FinanceKitBatchUploadError(kind: .authentication)
  static let authorization = FinanceKitBatchUploadError(kind: .authorization)
  static let conflict = FinanceKitBatchUploadError(kind: .conflict)
  static let invalidResponse = FinanceKitBatchUploadError(kind: .invalidResponse)
  static let publisherRevoked = FinanceKitBatchUploadError(kind: .publisherRevoked)
  static let rejected = FinanceKitBatchUploadError(kind: .rejected)
  static let tooLarge = FinanceKitBatchUploadError(kind: .tooLarge)

  static func rateLimited(retryAfter: Int?) -> Self {
    FinanceKitBatchUploadError(kind: .rateLimited(retryAfter: retryAfter))
  }

  static func server(_ status: Int) -> Self {
    FinanceKitBatchUploadError(kind: .server(status))
  }
}
