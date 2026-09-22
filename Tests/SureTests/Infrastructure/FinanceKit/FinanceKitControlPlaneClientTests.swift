import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit control plane")
struct FinanceKitControlPlaneClientTests {
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
