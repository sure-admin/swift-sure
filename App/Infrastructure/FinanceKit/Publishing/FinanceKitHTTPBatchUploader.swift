import Foundation

struct FinanceKitHTTPBatchUploader: FinanceKitBatchUploading {
  var dataTransport: any HTTPDataTransport
  var credential: String
  var canUpload: @Sendable () -> Bool = { true }

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
    for attempt in 0..<10 {
      if attempt > 0 { try await Task.sleep(for: .seconds(min(1 << attempt, 30))) }
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
    throw FinanceKitBatchUploadError.server(504)
  }

  private func decodeReceipt(data: Data, response: URLResponse) throws -> FinanceKitBatchReceipt {
    guard let http = response as? HTTPURLResponse else { throw FinanceKitBatchUploadError.invalidResponse }
    guard [200, 202].contains(http.statusCode) else { throw Self.error(for: http) }
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

  private static func error(for response: HTTPURLResponse) -> FinanceKitBatchUploadError {
    switch response.statusCode {
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
