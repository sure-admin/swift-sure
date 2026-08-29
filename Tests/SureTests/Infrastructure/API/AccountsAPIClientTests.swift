import Foundation
import Testing
@testable import Sure

@Suite("Accounts API client")
struct AccountsAPIClientTests {
  @Test("Aggregates every page and preserves signed currency values")
  func paginationAndMapping() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "accounts-page-1"),
      try .http(fixture: "accounts-page-2")
    ])
    let records = try await AccountsAPIClient(transport: makeTransport(stub)).fetchAll()

    #expect(records.map(\.id.uuidString) == [
      "00000000-0000-4000-8000-000000000101",
      "00000000-0000-4000-8000-000000000102",
      "00000000-0000-4000-8000-000000000103"
    ])
    #expect(records[1].balance.minorUnits == -42_015)
    #expect(records[1].balance.currency.rawValue == "EUR")
    #expect(records[2].balance.minorUnits == 250_000)
    #expect(records[2].balance.currency.minorUnitDigits == 0)
    #expect(records[2].balance.decimalValue == Decimal(250_000))

    let requests = await stub.requests()
    #expect(requests.count == 2)
    #expect(queryValue("page", in: requests[0]) == "1")
    #expect(queryValue("page", in: requests[1]) == "2")
    #expect(queryValue("per_page", in: requests[0]) == "100")
  }

  @Test("Treats an empty collection as a successful result")
  func emptyCollection() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "accounts-empty")])
    let records = try await AccountsAPIClient(transport: makeTransport(stub)).fetchAll()
    #expect(records.isEmpty)
  }

  @Test("Fails the whole collection when a required server ID is missing")
  func malformedAccount() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "accounts-malformed")])
    do {
      _ = try await AccountsAPIClient(transport: makeTransport(stub)).fetchAll()
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .decoding)
    }
  }

  @Test("Propagates a later-page failure instead of returning partial records")
  func laterPageFailure() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "accounts-page-1"),
      try .http(fixture: "error-unauthorized", status: 401)
    ])
    do {
      _ = try await AccountsAPIClient(transport: makeTransport(stub)).fetchAll()
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .unauthorized)
    }
  }

  private func makeTransport(_ stub: HTTPDataTransportStub) -> SureAPITransport {
    SureAPITransport(
      baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer()
    )
  }

  private func queryValue(_ name: String, in request: URLRequest) -> String? {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    return components.queryItems?.first { $0.name == name }?.value
  }
}
