import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit control plane")
struct FinanceKitControlPlaneClientTests {
  @Test("Deferred disconnects are sent only to their original server", arguments: [true, false])
  func serverBoundDisconnect(sameServer: Bool) async throws {
    let originalServer = URL(string: "https://sure.example")!
    let stub = HTTPDataTransportStub([try .http(status: 204)])
    let currentServer = sameServer ? originalServer : URL(string: "https://different.sure.example")!
    let client = FinanceKitControlPlaneClient(transport: SureAPITransport(baseURL: currentServer,
      dataTransport: stub, authorizer: HeaderRequestAuthorizer(name: "Authorization", value: "Bearer synthetic")))
    if sameServer {
      try await client.disconnect(connectionID: Self.connectionID, serverURL: originalServer)
      let requests = await stub.requests()
      #expect(requests.count == 1)
      #expect(requests.first?.httpMethod == "DELETE")
      #expect(requests.first?.url?.host == originalServer.host)
    } else {
      await #expect(throws: CancellationError.self) {
        try await client.disconnect(connectionID: Self.connectionID, serverURL: originalServer)
      }
      #expect(await stub.requests().isEmpty)
    }
  }

  @Test("Reads every Wallet mapping page with user authorization and canonical IDs")
  func paginatedMappings() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "financekit-mappings-page-1"),
      try .http(fixture: "financekit-mappings-page-2")])
    let transport = SureAPITransport(baseURL: URL(string: "https://sure.example")!, dataTransport: stub,
      authorizer: HeaderRequestAuthorizer(name: "X-Api-Key", value: "synthetic-key"))
    let records = try await FinanceKitControlPlaneClient(transport: transport).accountMappings(connectionID: Self.connectionID)
    #expect(records.map(\.accountID) == [UUID(uuidString: "00000000-0000-4000-8000-000000000101"),
      UUID(uuidString: "00000000-0000-4000-8000-000000000102")])
    let requests = await stub.requests()
    #expect(requests.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value } == ["1", "2"])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Api-Key") == "synthetic-key" })
  }

  @Test("No mappings is a successful empty response")
  func emptyMappings() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "financekit-mappings-empty")])
    #expect(try await mappingClient(stub).accountMappings(connectionID: Self.connectionID).isEmpty)
  }

  @Test("Rejects malformed identity and incomplete or repeated pages", arguments: ["financekit-mappings-malformed", "financekit-mappings-page-1"])
  func malformedMappings(fixture: String) async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: fixture), try .http(fixture: "financekit-mappings-page-1")])
    await #expect(throws: SureAPIError.decoding) {
      _ = try await mappingClient(stub).accountMappings(connectionID: Self.connectionID)
    }
  }

  @Test("Later mapping-page auth errors cannot produce partial matches")
  func mappingFailure() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "financekit-mappings-page-1"),
      try .http(fixture: "error-unauthorized", status: 401)])
    await #expect(throws: SureAPIError.unauthorized) {
      _ = try await mappingClient(stub).accountMappings(connectionID: Self.connectionID)
    }
  }

  @Test("Account reads enrich only the canonical IDs named by Wallet mappings")
  func accountProvenance() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "accounts-page-1"), try .http(fixture: "accounts-page-2"),
      try .http(fixture: "financekit-mappings-page-1"), try .http(fixture: "financekit-mappings-page-2")])
    let client = SureAPIClient(transport: SureAPITransport(baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub, authorizer: UnauthenticatedRequestAuthorizer()), walletConnectionID: { Self.connectionID })
    let accounts = try await client.fetchAccounts()
    #expect(accounts[0].walletSourceAccountID == UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
    #expect(accounts[1].displayInstitution == "Apple Wallet")
    #expect(accounts[2].walletSourceAccountID == nil)
  }

  private static let connectionID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
  private func mappingClient(_ stub: HTTPDataTransportStub) -> FinanceKitControlPlaneClient {
    FinanceKitControlPlaneClient(transport: SureAPITransport(baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub, authorizer: UnauthenticatedRequestAuthorizer()))
  }

  @Test("Uses authenticated Sure transport for health and remote disconnect")
  func healthAndDisconnect() async throws {
    let id = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"connection_id":"20000000-0000-4000-8000-000000000001","status":"active","repair_reason":null,"open_conflicts":0,"last_device_contact_at":null,"last_imported_at":null}"#),
      try .http(status: 204)
    ])
    let transport = SureAPITransport(baseURL: URL(string: "https://sure.example")!, dataTransport: stub,
      authorizer: HeaderRequestAuthorizer(name: "Authorization", value: "Bearer test"))
    let client = FinanceKitControlPlaneClient(transport: transport)

    let health = try await client.health(connectionID: id)
    try await client.disconnect(connectionID: id)

    #expect(health.status == "active")
    let requests = await stub.requests()
    #expect(requests.map(\.httpMethod) == ["GET", "DELETE"])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test" })
    #expect(requests[1].url?.path == "/api/v1/financekit/connections/20000000-0000-4000-8000-000000000001")
  }

  @Test("Decodes the activation contract into a validated publisher configuration")
  func activation() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "financekit-activation")])
    let transport = SureAPITransport(baseURL: URL(string: "https://sure.example")!, dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer())
    let value = try await FinanceKitControlPlaneClient(transport: transport)
      .activate(connectionID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!)

    // Rails returns a plain credential string beside the config fields; there is
    // no crypto envelope to unwrap.
    #expect(value.publisherCredential == "publisher-secret")
    let configuration = try value.configuration()
    #expect(configuration.protocolVersion == FinanceKitPublisherConfiguration.currentProtocolVersion)
    #expect(configuration.connectionID == UUID(uuidString: "20000000-0000-4000-8000-000000000001"))
    #expect(configuration.publisherID == UUID(uuidString: "30000000-0000-4000-8000-000000000001"))
    #expect(configuration.generation == 3)
    #expect(configuration.streamID == UUID(uuidString: "40000000-0000-4000-8000-000000000001"))
    #expect(configuration.uploadURL.path == "/api/v1/financekit/publishers/30000000-0000-4000-8000-000000000001/batches")
    #expect(configuration.maxRecordsPerBatch == 500)
    #expect(configuration.maxBytesPerBatch == 5_000_000)
    #expect(configuration.accountBindings.map(\.mappingVersion) == [2])
    #expect(configuration.accountBindings.map(\.lineageID) == [UUID(uuidString: "10000000-0000-4000-8000-000000000001")!])
    #expect(configuration.consent.selectedSourceAccountIDs == [UUID(uuidString: "00000000-0000-4000-8000-000000000001")!])
    #expect(configuration.consent.grantedAt == Date(timeIntervalSince1970: 1_789_689_600))
  }

  @Test("Keeps the server's device-contact, accepted, imported and downstream times apart")
  func healthTimestampsStayDistinct() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "financekit-connection-health")])
    let transport = SureAPITransport(baseURL: URL(string: "https://sure.example")!, dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer())
    let health = try await FinanceKitControlPlaneClient(transport: transport)
      .health(connectionID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!)

    #expect(health.status == "active")
    #expect(health.openConflicts == 1)
    #expect(health.lastDeviceContactAt == Date(timeIntervalSince1970: 1_789_725_600))
    #expect(health.lastAcceptedAt == Date(timeIntervalSince1970: 1_789_725_601))
    #expect(health.lastImportedAt == Date(timeIntervalSince1970: 1_789_725_604))
    #expect(health.lastDownstreamAt == Date(timeIntervalSince1970: 1_789_725_900))
  }
}
