import Foundation

enum APIForbiddenResponse {
  case authorization
  case featureUnavailable
  case previewFeatureUnavailable
}

struct APIRequest<Response> {
  var method: HTTPMethod
  var pathComponents: [String]
  var queryItems: [URLQueryItem]
  var expectedStatusCodes: Set<Int>
  var forbiddenResponse: APIForbiddenResponse

  private var encodedBody: ((JSONEncoder) throws -> Data)?
  private var decodedResponse: (Data, JSONDecoder) throws -> Response

  func encodeBody(using encoder: JSONEncoder) throws -> Data? {
    try encodedBody?(encoder)
  }

  func decodeResponse(from data: Data, using decoder: JSONDecoder) throws -> Response {
    try decodedResponse(data, decoder)
  }
}

extension APIRequest where Response: Decodable {
  init(
    method: HTTPMethod,
    pathComponents: [String],
    queryItems: [URLQueryItem] = [],
    expectedStatusCodes: Set<Int> = [200],
    forbiddenResponse: APIForbiddenResponse = .authorization
  ) {
    self.method = method
    self.pathComponents = pathComponents
    self.queryItems = queryItems
    self.expectedStatusCodes = expectedStatusCodes
    self.forbiddenResponse = forbiddenResponse
    encodedBody = nil
    decodedResponse = { data, decoder in
      try decoder.decode(Response.self, from: data)
    }
  }

  init<Body: Encodable>(
    method: HTTPMethod,
    pathComponents: [String],
    queryItems: [URLQueryItem] = [],
    body: Body,
    expectedStatusCodes: Set<Int> = [200],
    forbiddenResponse: APIForbiddenResponse = .authorization
  ) {
    self.method = method
    self.pathComponents = pathComponents
    self.queryItems = queryItems
    self.expectedStatusCodes = expectedStatusCodes
    self.forbiddenResponse = forbiddenResponse
    encodedBody = { encoder in
      try encoder.encode(body)
    }
    decodedResponse = { data, decoder in
      try decoder.decode(Response.self, from: data)
    }
  }
}

extension APIRequest where Response == Void {
  init(
    method: HTTPMethod,
    pathComponents: [String],
    queryItems: [URLQueryItem] = [],
    expectedStatusCodes: Set<Int> = [204],
    forbiddenResponse: APIForbiddenResponse = .authorization
  ) {
    self.method = method
    self.pathComponents = pathComponents
    self.queryItems = queryItems
    self.expectedStatusCodes = expectedStatusCodes
    self.forbiddenResponse = forbiddenResponse
    encodedBody = nil
    decodedResponse = { _, _ in () }
  }

  init<Body: Encodable>(
    method: HTTPMethod,
    pathComponents: [String],
    queryItems: [URLQueryItem] = [],
    body: Body,
    expectedStatusCodes: Set<Int> = [204],
    forbiddenResponse: APIForbiddenResponse = .authorization
  ) {
    self.method = method
    self.pathComponents = pathComponents
    self.queryItems = queryItems
    self.expectedStatusCodes = expectedStatusCodes
    self.forbiddenResponse = forbiddenResponse
    encodedBody = { encoder in
      try encoder.encode(body)
    }
    decodedResponse = { _, _ in () }
  }
}
