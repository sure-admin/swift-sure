import Foundation

struct FinanceKitControlPlaneClient: Sendable {
  var transport: SureAPITransport

  func capabilities() async throws -> FinanceKitCapabilities {
    try await transport.send(APIRequest(method: .get, pathComponents: path("capabilities")))
  }

  func enroll(_ request: FinanceKitEnrollmentRequest) async throws -> FinanceKitConnectionRecord {
    try await transport.send(APIRequest(method: .post, pathComponents: path("connections"), body: request,
      expectedStatusCodes: [200, 201], forbiddenResponse: .previewFeatureUnavailable))
  }

  func map(connectionID: UUID, account: FinanceKitAccountMappingRequest) async throws -> FinanceKitAccountMappingRecord {
    try await transport.send(APIRequest(method: .put,
      pathComponents: path("connections", connectionID.uuidString.lowercased(), "account_mappings", account.sourceID.uuidString.lowercased()),
      body: account.body, forbiddenResponse: .previewFeatureUnavailable))
  }

  func activate(connectionID: UUID) async throws -> FinanceKitActivation {
    try await transport.send(APIRequest(method: .post,
      pathComponents: path("connections", connectionID.uuidString.lowercased(), "activate"),
      forbiddenResponse: .previewFeatureUnavailable))
  }

  func health(connectionID: UUID) async throws -> FinanceKitConnectionRecord {
    try await transport.send(APIRequest(method: .get,
      pathComponents: path("connections", connectionID.uuidString.lowercased()),
      forbiddenResponse: .previewFeatureUnavailable))
  }

  /// Connection mappings are paginated independently of the account collection.
  func accountMappings(connectionID: UUID) async throws -> [FinanceKitAccountMappingRecord] {
    var page = 1
    var expectedCount: Int?
    var records: [FinanceKitAccountMappingRecord] = []
    while true {
      try Task.checkCancellation()
      let response: FinanceKitAccountMappingPage = try await transport.send(APIRequest(method: .get,
        pathComponents: path("connections", connectionID.uuidString.lowercased()),
        queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: "100")],
        forbiddenResponse: .previewFeatureUnavailable))
      let pagination = response.pagination
      guard response.connectionID == connectionID, pagination.page == page,
            (1...100).contains(pagination.perPage), pagination.totalCount >= 0,
            expectedCount == nil || expectedCount == pagination.totalCount,
            pagination.totalPages == (pagination.totalCount == 0 ? 0 : (pagination.totalCount - 1) / pagination.perPage + 1),
            response.accounts.count <= pagination.perPage,
            pagination.totalCount == 0 || !response.accounts.isEmpty else { throw SureAPIError.decoding }
      expectedCount = pagination.totalCount
      records += response.accounts
      guard records.count <= pagination.totalCount,
            Set(records.map(\.sourceID)).count == records.count,
            Set(records.map(\.lineageID)).count == records.count,
            Set(records.compactMap(\.accountID)).count == records.compactMap(\.accountID).count,
            records.allSatisfy({ $0.mappingVersion > 0 }) else { throw SureAPIError.decoding }
      if page >= pagination.totalPages {
        guard records.count == pagination.totalCount else { throw SureAPIError.decoding }
        return records
      }
      page += 1
    }
  }

  func renew(connectionID: UUID) async throws -> FinanceKitActivation {
    try await command("credential", connectionID: connectionID)
  }

  func repair(connectionID: UUID) async throws -> FinanceKitActivation {
    try await command("repair", connectionID: connectionID)
  }

  func conflicts(connectionID: UUID) async throws -> FinanceKitConflictCollection {
    try await transport.send(APIRequest(method: .get,
      pathComponents: path("connections", connectionID.uuidString.lowercased(), "conflicts"),
      forbiddenResponse: .previewFeatureUnavailable))
  }

  func resolve(connectionID: UUID, conflictID: UUID, resolution: String) async throws -> FinanceKitConflictRecord {
    try await transport.send(APIRequest(method: .patch,
      pathComponents: path("connections", connectionID.uuidString.lowercased(), "conflicts", conflictID.uuidString.lowercased()),
      body: ["resolution": resolution], forbiddenResponse: .previewFeatureUnavailable))
  }

  func disconnect(connectionID: UUID) async throws {
    try await transport.send(APIRequest<Void>(method: .delete,
      pathComponents: path("connections", connectionID.uuidString.lowercased()),
      forbiddenResponse: .previewFeatureUnavailable))
  }

  private func command(_ command: String, connectionID: UUID) async throws -> FinanceKitActivation {
    try await transport.send(APIRequest(method: .post,
      pathComponents: path("connections", connectionID.uuidString.lowercased(), command),
      forbiddenResponse: .previewFeatureUnavailable))
  }

  private func path(_ components: String...) -> [String] { ["api", "v1", "financekit"] + components }
}

struct FinanceKitCapabilities: Decodable, Sendable { var available: Bool }
struct FinanceKitConnectionRecord: Decodable, Sendable {
  var connectionID: UUID
  var status: String
  var repairReason: String?
  var openConflicts: Int
  var lastDeviceContactAt: Date?
  var lastAcceptedAt: Date?
  var lastImportedAt: Date?
  var lastDownstreamAt: Date?
  enum CodingKeys: String, CodingKey { case connectionID = "connection_id", status
    case repairReason = "repair_reason", openConflicts = "open_conflicts"
    case lastDeviceContactAt = "last_device_contact_at", lastAcceptedAt = "last_accepted_at"
    case lastImportedAt = "last_imported_at", lastDownstreamAt = "last_downstream_at" }
}
struct FinanceKitConflictCollection: Decodable, Sendable { var conflicts: [FinanceKitConflictRecord] }
struct FinanceKitConflictRecord: Decodable, Identifiable, Sendable {
  var id: UUID; var kind: String; var status: String; var details: [String: String]?
}
struct FinanceKitActivation: Decodable, Sendable {
  var protocolVersion: Int; var serverURL: URL; var uploadURL: URL; var connectionID: UUID; var publisherID: UUID
  var generation: UInt64; var streamID: UUID; var consent: FinanceKitUploadConsent
  var accountBindings: [FinanceKitAccountBinding]; var maxRecordsPerBatch: Int; var maxBytesPerBatch: Int
  var publisherCredential: String
  enum CodingKeys: String, CodingKey { case protocolVersion = "protocol_version", serverURL = "server_url"
    case uploadURL = "upload_url", connectionID = "connection_id", publisherID = "publisher_id", generation
    case streamID = "stream_id", consent, accountBindings = "account_bindings"
    case maxRecordsPerBatch = "max_records_per_batch", maxBytesPerBatch = "max_bytes_per_batch"
    case publisherCredential = "publisher_credential" }
  func configuration() throws -> FinanceKitPublisherConfiguration {
    try FinanceKitPublisherConfiguration(protocolVersion: protocolVersion, serverURL: serverURL, uploadURL: uploadURL,
      connectionID: connectionID, publisherID: publisherID, generation: generation, streamID: streamID,
      consent: consent, accountBindings: accountBindings, maxRecordsPerBatch: maxRecordsPerBatch,
      maxBytesPerBatch: maxBytesPerBatch)
  }
}
struct FinanceKitEnrollmentRequest: Encodable, Sendable {
  var enrollmentID: UUID; var protocolVersion = FinanceKitPublisherConfiguration.currentProtocolVersion
  var consent: FinanceKitUploadConsent
  enum CodingKeys: String, CodingKey { case enrollmentID = "enrollment_id", protocolVersion = "protocol_version", consent }
}
struct FinanceKitAccountMappingRequest: Sendable {
  var sourceID: UUID; var body: Body
  struct Body: Encodable, Sendable {
    var expectedVersion = 0; var action = "create"; var name: String; var institutionName: String; var currency: String
    var accountableType: String; var subtype: String; var ledgerTimezone: String
    var bookedBalance: MoneyBody; var observedAt: Date
    enum CodingKeys: String, CodingKey { case expectedVersion = "expected_version", action, name
      case institutionName = "institution_name", currency, accountableType = "accountable_type", subtype
      case ledgerTimezone = "ledger_timezone", bookedBalance = "booked_balance", observedAt = "observed_at" }
  }
  struct MoneyBody: Encodable, Sendable { var amount: String; var currency: String; var direction: String }
}
struct FinanceKitAccountMappingRecord: Decodable, Sendable {
  var sourceID: UUID; var lineageID: UUID; var mappingVersion: Int
  var accountID: UUID?

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sourceID = try container.decode(UUID.self, forKey: .sourceID)
    lineageID = try container.decode(UUID.self, forKey: .lineageID)
    mappingVersion = try container.decode(Int.self, forKey: .mappingVersion)
    accountID = try container.decode(UUID?.self, forKey: .accountID)
  }

  enum CodingKeys: String, CodingKey { case sourceID = "source_id", lineageID = "lineage_id", mappingVersion = "mapping_version", accountID = "account_id" }
}

private struct FinanceKitAccountMappingPage: Decodable {
  var connectionID: UUID
  var accounts: [FinanceKitAccountMappingRecord]
  var pagination: PaginationDTO
  enum CodingKeys: String, CodingKey { case connectionID = "connection_id", accounts, pagination }
}
