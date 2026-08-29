import Foundation

protocol HTTPDataTransport {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPDataTransport: HTTPDataTransport {
  var session: URLSession

  init(session: URLSession) {
    self.session = session
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: request)
  }
}
