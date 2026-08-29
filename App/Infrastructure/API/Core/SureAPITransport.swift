import Foundation

struct SureAPITransport {
  private var baseURL: () throws -> URL
  private var dataTransport: any HTTPDataTransport
  private var authorizer: any RequestAuthorizing
  private var timeoutInterval: TimeInterval
  private var makeDecoder: () -> JSONDecoder
  private var makeEncoder: () -> JSONEncoder

  init(
    baseURL: URL,
    dataTransport: any HTTPDataTransport,
    authorizer: any RequestAuthorizing,
    timeoutInterval: TimeInterval = 60,
    makeDecoder: @escaping () -> JSONDecoder = Self.defaultDecoder,
    makeEncoder: @escaping () -> JSONEncoder = Self.defaultEncoder
  ) {
    self.baseURL = { baseURL }
    self.dataTransport = dataTransport
    self.authorizer = authorizer
    self.timeoutInterval = timeoutInterval
    self.makeDecoder = makeDecoder
    self.makeEncoder = makeEncoder
  }

  init(
    baseURL: @escaping () throws -> URL,
    dataTransport: any HTTPDataTransport,
    authorizer: any RequestAuthorizing,
    timeoutInterval: TimeInterval = 60,
    makeDecoder: @escaping () -> JSONDecoder = Self.defaultDecoder,
    makeEncoder: @escaping () -> JSONEncoder = Self.defaultEncoder
  ) {
    self.baseURL = baseURL
    self.dataTransport = dataTransport
    self.authorizer = authorizer
    self.timeoutInterval = timeoutInterval
    self.makeDecoder = makeDecoder
    self.makeEncoder = makeEncoder
  }

  func send<Response>(_ apiRequest: APIRequest<Response>) async throws -> Response {
    try Task.checkCancellation()

    var request = URLRequest(url: try url(for: apiRequest))
    request.httpMethod = apiRequest.method.rawValue
    request.timeoutInterval = timeoutInterval
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      if let body = try apiRequest.encodeBody(using: makeEncoder()) {
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw SureAPIError.encoding
    }

    authorizer.authorize(&request)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await dataTransport.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch {
      throw SureAPIError.transport
    }

    try Task.checkCancellation()

    guard let httpResponse = response as? HTTPURLResponse else {
      throw SureAPIError.invalidResponse
    }
    guard apiRequest.expectedStatusCodes.contains(httpResponse.statusCode) else {
      let errorResponse = try? makeDecoder().decode(ErrorResponseDTO.self, from: data)
      throw error(
        for: httpResponse.statusCode,
        forbiddenResponse: apiRequest.forbiddenResponse,
        errorResponse: errorResponse
      )
    }

    do {
      return try apiRequest.decodeResponse(from: data, using: makeDecoder())
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw SureAPIError.decoding
    }
  }

  private func url<Response>(for apiRequest: APIRequest<Response>) throws -> URL {
    let baseURL = try baseURL()
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
          let scheme = components.scheme?.lowercased(),
          let host = components.host,
          scheme == "https" || Self.allowsDevelopmentHTTP(scheme: scheme, host: host),
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil else {
      throw SureAPIError.invalidURL
    }

    var allowedPathCharacters = CharacterSet.urlPathAllowed
    allowedPathCharacters.remove(charactersIn: "/?#%")
    var path = components.percentEncodedPath
    if path == "/" {
      path = ""
    } else if path.hasSuffix("/") {
      path.removeLast()
    }
    for pathComponent in apiRequest.pathComponents {
      guard !pathComponent.isEmpty,
            pathComponent != ".",
            pathComponent != "..",
            let encoded = pathComponent.addingPercentEncoding(
              withAllowedCharacters: allowedPathCharacters
            ) else {
        throw SureAPIError.invalidURL
      }
      path += "/\(encoded)"
    }
    components.percentEncodedPath = path.isEmpty ? "/" : path
    components.queryItems = apiRequest.queryItems.isEmpty ? nil : apiRequest.queryItems
    components.fragment = nil

    guard let url = components.url else {
      throw SureAPIError.invalidURL
    }
    return url
  }

  private static func allowsDevelopmentHTTP(scheme: String, host: String) -> Bool {
    #if DEBUG
    guard scheme == "http" else { return false }
    return ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    #else
    return false
    #endif
  }

  private func error(
    for statusCode: Int,
    forbiddenResponse: APIForbiddenResponse,
    errorResponse: ErrorResponseDTO?
  ) -> SureAPIError {
    switch statusCode {
    case 401:
      .unauthorized
    case 403:
      forbiddenError(
        serverCode: errorResponse?.normalizedErrorCode,
        fallback: forbiddenResponse
      )
    case 404:
      .notFound
    case 422:
      .validation
    case 429:
      .rateLimited
    case 500...599:
      .server(statusCode)
    default:
      .unexpectedStatus(statusCode)
    }
  }

  private func forbiddenError(
    serverCode: String?,
    fallback: APIForbiddenResponse
  ) -> SureAPIError {
    if let serverCode,
       serverCode.contains("insufficient_scope") || serverCode == "forbidden" {
      return .forbidden
    }

    if let serverCode,
       serverCode.contains("feature") && serverCode.contains("disabled") {
      switch fallback {
      case .authorization:
        return .featureUnavailable
      case .featureUnavailable:
        return .featureUnavailable
      case .previewFeatureUnavailable:
        return .previewFeatureUnavailable
      }
    }

    switch fallback {
    case .authorization:
      return .forbidden
    case .featureUnavailable:
      return .featureUnavailable
    case .previewFeatureUnavailable:
      return .previewFeatureUnavailable
    }
  }

  private static func defaultDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let fractionalFormatter = ISO8601DateFormatter()
      fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractionalFormatter.date(from: value) {
        return date
      }
      if let date = ISO8601DateFormatter().date(from: value) {
        return date
      }

      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.isLenient = false
      if let date = formatter.date(from: value) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected an ISO 8601 date or date-time."
      )
    }
    return decoder
  }

  private static func defaultEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}
