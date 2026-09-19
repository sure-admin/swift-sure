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

  @Test("Decodes activation fixture into validated publisher configuration")
  func activation() async throws {
    let stub = HTTPDataTransportStub([try .http(json: Self.activationJSON)])
    let transport = SureAPITransport(baseURL: URL(string: "https://sure.example")!, dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer())
    let value = try await FinanceKitControlPlaneClient(transport: transport)
      .activate(connectionID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!)
    #expect(try value.configuration().accountBindings.count == 1)
    #expect(value.publisherCredential == "publisher-secret")
  }

  private static let activationJSON = #"{"protocol_version":2,"server_url":"https://sure.example","upload_url":"https://sure.example/api/v1/financekit/publishers/30000000-0000-4000-8000-000000000001/batches","connection_id":"20000000-0000-4000-8000-000000000001","publisher_id":"30000000-0000-4000-8000-000000000001","generation":1,"stream_id":"40000000-0000-4000-8000-000000000001","consent":{"version":1,"granted_at":"2026-09-18T00:00:00Z","selected_source_account_ids":["00000000-0000-4000-8000-000000000001"],"upload_authorized":true,"family_visibility_acknowledged":true,"remote_processing_acknowledged":true},"account_bindings":[{"source_account_id":"00000000-0000-4000-8000-000000000001","lineage_id":"10000000-0000-4000-8000-000000000001","mapping_version":1}],"max_records_per_batch":500,"max_bytes_per_batch":5000000,"publisher_credential":"publisher-secret"}"#
}
