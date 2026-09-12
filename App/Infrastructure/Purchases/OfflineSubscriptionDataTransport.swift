import Foundation

struct OfflineSubscriptionDataTransport: HTTPDataTransport {
  var base: any HTTPDataTransport
  var gate: BackendAccessGate
  var cache: OfflineAPIResponseStore
  var identity: @Sendable () async -> String?

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    guard request.httpMethod == "GET", let url = request.url,
          let scope = await identity() else { return try await base.data(for: request) }
    let key = scope + "\n" + url.absoluteString
    if !gate.isAllowed {
      guard let data = try await cache.read(key: key), await identity() == scope else {
        throw BackendAccessError.subscriptionRequired
      }
      try Task.checkCancellation()
      return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                   headerFields: ["Content-Type": "application/json"])!)
    }
    let result = try await base.data(for: request)
    guard await identity() == scope else { throw CancellationError() }
    if (result.1 as? HTTPURLResponse)?.statusCode == 200 {
      try await cache.write(result.0, key: key)
    }
    return result
  }
}
