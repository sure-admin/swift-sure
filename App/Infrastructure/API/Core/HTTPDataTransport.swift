import Foundation

protocol HTTPDataTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPDataTransport: HTTPDataTransport, @unchecked Sendable {
  var session: URLSession

  init(session: URLSession) {
    self.session = session
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: request)
  }
}
