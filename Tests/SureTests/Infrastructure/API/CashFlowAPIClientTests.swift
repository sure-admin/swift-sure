import Foundation
import Testing
@testable import Sure

@Suite("Cash flow contract")
@MainActor
struct CashFlowAPIClientTests {
  @Test("Reads the bounded documented endpoint and preserves FX precision")
  func mapping() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "cash-flow-success")])
    let expected = try summaryFixture()
    let actual = try await client(stub).fetchSummary(for: expected.month)
    #expect(actual == expected)
    #expect(actual.savingsRate == Decimal(string: "0.967655"))
    #expect(actual.comparison.previous.count == 31)
    #expect(actual.comparison.previousTotal == 10)
    let request = try #require(await stub.requests().first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/v1/cash_flow")
    #expect(request.url?.query == "month=2024-02-01&include=sankey")
  }

  @Test("Zero income keeps savings rate unavailable")
  func empty() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "cash-flow-empty")])
    let result = try await client(stub).fetchSummary(for: summaryFixture().month)
    #expect(result.savingsRate == nil)
    #expect(result.comparison.isEmpty)
  }

  @Test("Rejects an incomplete daily series")
  func malformed() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "cash-flow-malformed")])
    await #expect(throws: SureAPIError.decoding) { _ = try await client(stub).fetchSummary(for: summaryFixture().month) }
  }

  @Test("Rejects a response for a different month")
  func mismatchedMonth() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "cash-flow-success")])
    await #expect(throws: SureAPIError.decoding) {
      _ = try await client(stub).fetchSummary(for: summaryFixture().month.shifted(by: -1))
    }
  }

  @Test("Preserves authentication, scope, and validation errors", arguments: [401, 403, 422])
  func documentedErrors(status: Int) async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "error-validation", status: status)])
    let expected: SureAPIError = status == 401 ? .unauthorized : status == 403 ? .forbidden : .validation
    await #expect(throws: expected) { _ = try await client(stub).fetchSummary(for: summaryFixture().month) }
  }

  @Test("A live response must include the requested graph")
  func missingGraph() async throws {
    var dto = try JSONDecoder().decode(CashFlowDTO.self, from: APIFixture.data(named: "cash-flow-success"))
    dto.sankey = nil
    let body = try JSONEncoder().encode(dto)
    let stub = HTTPDataTransportStub([try .http(json: String(decoding: body, as: UTF8.self))])
    await #expect(throws: SureAPIError.decoding) {
      _ = try await client(stub).fetchSummary(for: summaryFixture().month)
    }
  }

  private func client(_ stub: HTTPDataTransportStub) -> CashFlowAPIClient {
    CashFlowAPIClient(transport: SureAPITransport(baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub, authorizer: UnauthenticatedRequestAuthorizer()))
  }
}
