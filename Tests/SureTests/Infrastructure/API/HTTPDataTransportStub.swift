import Foundation
@testable import Sure

actor HTTPDataTransportStub: HTTPDataTransport {
  enum Result {
    case response(data: Data, response: URLResponse)
    case failure(any Error)

    static func http(
      fixture: String? = nil,
      json: String? = nil,
      status: Int = 200,
      headers: [String: String]? = nil,
      url: URL = URL(string: "https://sure.example")!
    ) throws -> Result {
      let data: Data
      if let fixture {
        data = try APIFixture.data(named: fixture)
      } else {
        data = Data((json ?? "").utf8)
      }
      let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
      )!
      return .response(data: data, response: response)
    }
  }

  private var queuedResults: [Result]
  private var recordedRequests: [URLRequest] = []

  init(_ queuedResults: [Result]) {
    self.queuedResults = queuedResults
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    recordedRequests.append(request)
    guard !queuedResults.isEmpty else {
      throw HTTPDataTransportStubError.missingResponse
    }
    switch queuedResults.removeFirst() {
    case .response(let data, let response):
      return (data, response)
    case .failure(let error):
      throw error
    }
  }

  func requests() -> [URLRequest] {
    recordedRequests
  }

}

private enum HTTPDataTransportStubError: Error {
  case missingResponse
}

struct HeaderRequestAuthorizer: RequestAuthorizing {
  var name: String
  var value: String

  func authorize(_ request: inout URLRequest) {
    request.setValue(value, forHTTPHeaderField: name)
  }
}
