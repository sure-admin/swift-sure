import Foundation
import Testing
@testable import Sure

@Suite("Transactions API client")
struct TransactionsAPIClientTests {
  @Test("Aggregates pages and maps signed minor units, account, date, and currency")
  func paginationAndMapping() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "transactions-page-1"),
      try .http(fixture: "transactions-page-2")
    ])
    let accountID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000101"))
    let query = TransactionQuery(
      accountIDs: [accountID],
      startDate: try LocalDate(year: 2026, month: 8, day: 1),
      endDate: try LocalDate(year: 2026, month: 8, day: 27),
      classification: .expense
    )
    let records = try await TransactionsAPIClient(transport: makeTransport(stub))
      .fetchAll(query: query)

    #expect(records.count == 3)
    #expect(records[0].accountID == accountID)
    #expect(records[0].signedAmount.minorUnits == -5_240)
    #expect(records[0].signedAmount.currency.rawValue == "USD")
    #expect(records[0].date.iso8601String == "2026-08-27")
    #expect(records[0].classification == .expense)
    #expect(records[1].signedAmount.minorUnits == 250_000)
    #expect(records[1].classification == .income)
    #expect(records[2].signedAmount.currency.rawValue == "JPY")
    #expect(records[2].signedAmount.decimalValue == Decimal(-850))

    let requests = await stub.requests()
    #expect(requests.count == 2)
    #expect(queryValues("page", in: requests[0]) == ["1"])
    #expect(queryValues("page", in: requests[1]) == ["2"])
    #expect(queryValues("per_page", in: requests[0]) == ["100"])
    #expect(queryValues("account_ids[]", in: requests[0]) == [accountID.uuidString.lowercased()])
    #expect(queryValues("start_date", in: requests[0]) == ["2026-08-01"])
    #expect(queryValues("end_date", in: requests[0]) == ["2026-08-27"])
    #expect(queryValues("type", in: requests[0]) == ["expense"])
  }

  @Test("Treats an empty collection as successful")
  func emptyCollection() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "transactions-empty")])
    let records = try await TransactionsAPIClient(transport: makeTransport(stub)).fetchAll()
    #expect(records.isEmpty)
  }

  @Test("Rejects malformed required transaction dates")
  func malformedDate() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "transactions-malformed-date")])
    do {
      _ = try await TransactionsAPIClient(transport: makeTransport(stub)).fetchAll()
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .decoding)
    }
  }

  @Test("Normalizes the pinned amount-cents compatibility fallback once")
  func amountCentsFallback() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "transactions-amount-cents-only")
    ])
    let records = try await TransactionsAPIClient(transport: makeTransport(stub)).fetchAll()

    #expect(records.map(\.signedAmount.minorUnits) == [-1_234, 5_678])
  }

  @Test("Rejects transactions without lossless minor-unit fields")
  func missingMinorUnits() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "transactions-missing-cents")
    ])
    do {
      _ = try await TransactionsAPIClient(transport: makeTransport(stub)).fetchAll()
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .decoding)
    }
  }

  private func makeTransport(_ stub: HTTPDataTransportStub) -> SureAPITransport {
    SureAPITransport(
      baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer()
    )
  }

  private func queryValues(_ name: String, in request: URLRequest) -> [String] {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return []
    }
    return components.queryItems?.filter { $0.name == name }.compactMap(\.value) ?? []
  }
}
