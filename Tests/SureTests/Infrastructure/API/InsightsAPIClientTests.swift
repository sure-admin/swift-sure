import Foundation
import Testing
@testable import Sure

@Suite("Insights API client")
struct InsightsAPIClientTests {
  @Test("Maps the documented typed insight collection")
  func success() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "insights-success")])
    let insights = try await InsightsAPIClient(transport: makeTransport(stub)).fetchInsights()

    #expect(insights.map(\.id) == [
      "00000000-0000-4000-8000-000000000601",
      "00000000-0000-4000-8000-000000000602"
    ])
    #expect(insights[0].type == "spending_change")
    #expect(insights[0].priority == "medium")
    #expect(insights[0].status == "active")
    #expect(insights[0].generatedAt == Date(timeIntervalSince1970: 1_787_832_000))
    #expect(insights[1].generatedAt == nil)
  }

  @Test("Treats an empty insight collection as successful")
  func empty() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "insights-empty")])
    let insights = try await InsightsAPIClient(transport: makeTransport(stub)).fetchInsights()
    #expect(insights.isEmpty)
  }

  @Test("Rejects unsupported required insight values")
  func malformed() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "insights-malformed")])
    do {
      _ = try await InsightsAPIClient(transport: makeTransport(stub)).fetchInsights()
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .decoding)
    }
  }

  @Test("Distinguishes preview gating from invalid credentials")
  func previewUnavailable() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "error-preview-disabled", status: 403)
    ])
    do {
      _ = try await InsightsAPIClient(transport: makeTransport(stub)).fetchInsights()
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .previewFeatureUnavailable)
    }
  }

  @Test("Acknowledges exactly one insight using the authenticated write endpoint")
  func acknowledge() async throws {
    let stub = HTTPDataTransportStub([try .http(status: 204)])
    let id = UUID(uuidString: "00000000-0000-4000-8000-000000000601")!
    try await InsightsAPIClient(transport: makeTransport(stub)).acknowledgeInsight(id: id)
    let request = try #require(await stub.requests().first)
    #expect(request.httpMethod == "PATCH")
    #expect(request.url?.path == "/api/v1/insights/" + id.uuidString + "/acknowledge")
    #expect(request.httpBody == nil)
  }

  @Test("A deferred acknowledgment cannot be redirected to a different configured server")
  func acknowledgmentServerBinding() async throws {
    let stub = HTTPDataTransportStub([])
    await #expect(throws: CancellationError.self) {
      try await InsightsAPIClient(transport: makeTransport(stub)).acknowledgeInsight(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000601")!,
        requiredServerURL: URL(string: "https://original.example")!)
    }
    #expect(await stub.requests().isEmpty)
  }

  @Test("Acknowledgment never treats a rejection or malformed success as dismissal",
        arguments: [401, 403, 404, 500, 200])
  func acknowledgmentFailures(status: Int) async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "error-insufficient-scope", status: status)])
    await #expect(throws: (any Error).self) {
      try await InsightsAPIClient(transport: makeTransport(stub))
        .acknowledgeInsight(id: UUID(uuidString: "00000000-0000-4000-8000-000000000601")!)
    }
  }

  private func makeTransport(_ stub: HTTPDataTransportStub) -> SureAPITransport {
    SureAPITransport(
      baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer()
    )
  }
}
