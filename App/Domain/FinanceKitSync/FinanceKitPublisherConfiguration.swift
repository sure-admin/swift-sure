import Foundation

struct FinanceKitPublisherConfiguration: Codable, Equatable, Sendable {
  static let currentProtocolVersion = 2

  var protocolVersion: Int
  var serverURL: URL
  var uploadURL: URL
  var connectionID: UUID
  var publisherID: UUID
  var generation: UInt64
  var streamID: UUID
  var consent: FinanceKitUploadConsent
  var accountBindings: [FinanceKitAccountBinding]
  var maxRecordsPerBatch: Int
  var maxBytesPerBatch: Int

  init(
    protocolVersion: Int = Self.currentProtocolVersion,
    serverURL: URL,
    uploadURL: URL,
    connectionID: UUID,
    publisherID: UUID,
    generation: UInt64,
    streamID: UUID,
    consent: FinanceKitUploadConsent,
    accountBindings: [FinanceKitAccountBinding],
    maxRecordsPerBatch: Int,
    maxBytesPerBatch: Int
  ) throws {
    guard protocolVersion == Self.currentProtocolVersion else {
      throw FinanceKitPublisherConfigurationError.invalidProtocolVersion
    }
    guard generation > 0 else {
      throw FinanceKitPublisherConfigurationError.invalidGeneration
    }
    guard (1...500).contains(maxRecordsPerBatch) else {
      throw FinanceKitPublisherConfigurationError.invalidRecordLimit
    }
    guard (1...5_000_000).contains(maxBytesPerBatch) else {
      throw FinanceKitPublisherConfigurationError.invalidByteLimit
    }
    let bindings = accountBindings.sorted { $0.sourceAccountID.uuidString < $1.sourceAccountID.uuidString }
    guard !bindings.isEmpty,
          Set(bindings.map(\.sourceAccountID)).count == bindings.count,
          Set(bindings.map(\.lineageID)).count == bindings.count,
          bindings.map(\.sourceAccountID) == consent.selectedSourceAccountIDs else {
      throw FinanceKitPublisherConfigurationError.invalidMapping
    }
    let normalizedServer = try Self.validatedServerURL(serverURL)
    let normalizedUpload = try Self.validatedUploadURL(uploadURL, serverURL: normalizedServer)
    self.protocolVersion = protocolVersion
    self.serverURL = normalizedServer
    self.uploadURL = normalizedUpload
    self.connectionID = connectionID
    self.publisherID = publisherID
    self.generation = generation
    self.streamID = streamID
    self.consent = consent
    self.accountBindings = bindings
    self.maxRecordsPerBatch = maxRecordsPerBatch
    self.maxBytesPerBatch = maxBytesPerBatch
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      protocolVersion: container.decode(Int.self, forKey: .protocolVersion),
      serverURL: container.decode(URL.self, forKey: .serverURL),
      uploadURL: container.decode(URL.self, forKey: .uploadURL),
      connectionID: container.decode(UUID.self, forKey: .connectionID),
      publisherID: container.decode(UUID.self, forKey: .publisherID),
      generation: container.decode(UInt64.self, forKey: .generation),
      streamID: container.decode(UUID.self, forKey: .streamID),
      consent: container.decode(FinanceKitUploadConsent.self, forKey: .consent),
      accountBindings: container.decode([FinanceKitAccountBinding].self, forKey: .accountBindings),
      maxRecordsPerBatch: container.decode(Int.self, forKey: .maxRecordsPerBatch),
      maxBytesPerBatch: container.decode(Int.self, forKey: .maxBytesPerBatch)
    )
  }

  private static func validatedServerURL(_ url: URL) throws -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let scheme = components.scheme?.lowercased(),
          let host = components.host?.lowercased(),
          !host.isEmpty,
          scheme == "https" || allowsDevelopmentHTTP(scheme: scheme, host: host),
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil else {
      throw FinanceKitPublisherConfigurationError.invalidServerURL
    }
    components.scheme = scheme
    components.host = host
    if scheme == "https", components.port == 443 { components.port = nil }
    while components.percentEncodedPath.hasSuffix("/") {
      components.percentEncodedPath.removeLast()
    }
    guard let normalized = components.url else {
      throw FinanceKitPublisherConfigurationError.invalidServerURL
    }
    return normalized
  }

  private static func validatedUploadURL(_ url: URL, serverURL: URL) throws -> URL {
    guard let upload = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let server = URLComponents(url: serverURL, resolvingAgainstBaseURL: false),
          upload.scheme?.lowercased() == server.scheme?.lowercased(),
          upload.host?.lowercased() == server.host?.lowercased(),
          normalizedPort(upload) == normalizedPort(server),
          upload.user == nil,
          upload.password == nil,
          upload.query == nil,
          upload.fragment == nil,
          !upload.percentEncodedPath.isEmpty,
          path(upload.percentEncodedPath, isWithin: server.percentEncodedPath) else {
      throw FinanceKitPublisherConfigurationError.invalidUploadURL
    }
    return url
  }

  private static func path(_ uploadPath: String, isWithin serverPath: String) -> Bool {
    let base = serverPath.hasSuffix("/") ? String(serverPath.dropLast()) : serverPath
    return base.isEmpty || uploadPath == base || uploadPath.hasPrefix(base + "/")
  }

  private static func normalizedPort(_ components: URLComponents) -> Int? {
    if let port = components.port { return port }
    return components.scheme?.lowercased() == "https" ? 443 : 80
  }

  private static func allowsDevelopmentHTTP(scheme: String, host: String) -> Bool {
    #if DEBUG
    scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    #else
    false
    #endif
  }
}
