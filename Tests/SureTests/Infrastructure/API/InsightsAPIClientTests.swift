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

  private func makeTransport(_ stub: HTTPDataTransportStub) -> SureAPITransport {
    SureAPITransport(
      baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer()
    )
  }
}
