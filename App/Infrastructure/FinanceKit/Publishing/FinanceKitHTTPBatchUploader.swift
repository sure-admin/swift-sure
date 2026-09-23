import Foundation

struct FinanceKitHTTPBatchUploader: FinanceKitBatchUploading {
  /// The server enqueues its import job on accept, so `applied` normally lands
  /// within seconds; the periodic sweep is only a recovery path. Five attempts
  /// spend about thirty seconds behind a foreground spinner, and anything slower
  /// resumes from the retained pending capture on the next pass.
  static let defaultStatusAttemptLimit = 5

  var dataTransport: any HTTPDataTransport
  var credential: String
  var canUpload: @Sendable () -> Bool = { true }
  var statusAttemptLimit = Self.defaultStatusAttemptLimit
  var waitBeforeStatusRetry: @Sendable (Int) async throws -> Void = { attempt in
    try await Task.sleep(for: .seconds(min(1 << attempt, 30)))
  }

  func upload(
    _ batch: FinanceKitPendingBatch,
    configuration: FinanceKitPublisherConfiguration
  ) async throws -> FinanceKitBatchReceipt {
    guard canUpload() else { throw FinanceKitBatchUploadError.publisherRevoked }
    var request = URLRequest(url: configuration.uploadURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.httpBody = batch.body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    request.setValue(batch.id.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
    request.setValue(batch.payloadDigest, forHTTPHeaderField: "X-Sure-Payload-SHA256")
    let (data, response) = try await dataTransport.data(for: request)
    return try decodeReceipt(data: data, response: response)
  }

  func status(
    _ batch: FinanceKitPendingBatch,
    configuration: FinanceKitPublisherConfiguration
  ) async throws -> FinanceKitBatchReceipt {
    guard canUpload() else { throw FinanceKitBatchUploadError.publisherRevoked }
    let statusURL = configuration.uploadURL.appendingPathComponent(batch.id.uuidString.lowercased())
    for attempt in 0..<statusAttemptLimit {
      if attempt > 0 { try await waitBeforeStatusRetry(attempt) }
      try Task.checkCancellation()
      guard canUpload() else { throw FinanceKitBatchUploadError.publisherRevoked }
      var request = URLRequest(url: statusURL)
      request.httpMethod = "GET"
      request.timeoutInterval = 30
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
      let (data, response) = try await dataTransport.data(for: request)
      let receipt = try decodeReceipt(data: data, response: response)
      guard receipt.connectionID == configuration.connectionID,
            receipt.publisherID == configuration.publisherID,
            receipt.generation == configuration.generation,
            receipt.streamID == configuration.streamID,
            receipt.batchID == batch.id,
            receipt.sequence == batch.sequence,
            receipt.payloadDigest == batch.payloadDigest else {
        throw FinanceKitBatchUploadError.invalidResponse
      }
      if receipt.status == .applied || receipt.status == .failed { return receipt }
    }
    throw FinanceKitSyncError.importPending
  }

  private func decodeReceipt(data: Data, response: URLResponse) throws -> FinanceKitBatchReceipt {
    guard let http = response as? HTTPURLResponse else { throw FinanceKitBatchUploadError.invalidResponse }
    guard [200, 202].contains(http.statusCode) else { throw Self.error(for: http, body: data) }
    do { return try Self.decoder().decode(FinanceKitBatchReceipt.self, from: data) }
    catch { throw FinanceKitBatchUploadError.invalidResponse }
  }

  static func live(
    gate: BackendAccessGate,
    credential: String,
    canUpload: @escaping @Sendable () -> Bool = { true }
  ) -> FinanceKitHTTPBatchUploader {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    let session = URLSession(
      configuration: configuration,
      delegate: FinanceKitRedirectRejectingDelegate(),
      delegateQueue: nil
    )
    return FinanceKitHTTPBatchUploader(
      dataTransport: SubscriptionHTTPDataTransport(
        base: URLSessionHTTPDataTransport(session: session),
        gate: gate
      ),
      credential: credential,
      canUpload: canUpload
    )
  }

  private static func error(
    for response: HTTPURLResponse,
    body: Data
  ) -> FinanceKitBatchUploadError {
    let kind: FinanceKitBatchUploadError.Kind = switch response.statusCode {
    case 401: .authentication
    case 403: .authorization
    case 409: .conflict
    case 413: .tooLarge
    case 422: .rejected
    case 429:
      .rateLimited(retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
    case 500...599: .server(response.statusCode)
    default: .invalidResponse
    }
    return FinanceKitBatchUploadError(kind: kind, code: protocolErrorCode(in: body))
  }

  /// Protocol errors arrive as `{"error": "<code>"}`. A body that is missing,
  /// empty, or shaped differently is not an error in itself; the status code
  /// already classified the failure.
  private static func protocolErrorCode(in body: Data) -> String? {
    guard !body.isEmpty,
          let envelope = try? JSONDecoder().decode(ProtocolErrorEnvelope.self, from: body),
          !envelope.error.isEmpty else { return nil }
    return envelope.error
  }

  private struct ProtocolErrorEnvelope: Decodable {
    var error: String
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: value) { return date }
      if let date = ISO8601DateFormatter().date(from: value) { return date }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected an ISO 8601 date-time."
      )
    }
    return decoder
  }
}

private final class FinanceKitRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
