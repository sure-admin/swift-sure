import Foundation
import Testing
@testable import Sure

@Suite("Balance sheet API client")
struct BalanceSheetAPIClientTests {
  @Test("Maps the authoritative balance sheet without losing currency precision")
  func mapping() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "balance-sheet-success")
    ])

    let record = try await BalanceSheetAPIClient(
      transport: makeTransport(stub)
    ).fetch()

    #expect(record.currency.rawValue == "USD")
    #expect(record.netWorth.minorUnits == 98_765_432_109)
    #expect(record.assets.minorUnits == 100_000_000_010)
    #expect(record.liabilities.minorUnits == 1_234_567_901)
    let request = try #require(await stub.requests().first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/v1/balance_sheet")
    #expect(request.url?.query == nil)
  }

  @Test("Rejects an amount with excess currency scale")
  func malformedMoney() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "balance-sheet-malformed")
    ])

    await #expect(throws: SureAPIError.decoding) {
      _ = try await BalanceSheetAPIClient(
        transport: makeTransport(stub)
      ).fetch()
    }
  }

  @Test("Rejects a nested currency that differs from the reporting currency")
  func inconsistentCurrency() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "balance-sheet-mismatched-currency")
    ])

    await #expect(throws: SureAPIError.decoding) {
      _ = try await BalanceSheetAPIClient(
        transport: makeTransport(stub)
      ).fetch()
    }
  }

  @Test("Preserves documented authentication failures")
  func authenticationFailure() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "error-unauthorized", status: 401)
    ])

    await #expect(throws: SureAPIError.unauthorized) {
      _ = try await BalanceSheetAPIClient(
        transport: makeTransport(stub)
      ).fetch()
    }
  }

  @Test("Preserves cancellation")
  func cancellation() async {
    let stub = HTTPDataTransportStub([.failure(CancellationError())])

    await #expect(throws: CancellationError.self) {
      _ = try await BalanceSheetAPIClient(
        transport: makeTransport(stub)
      ).fetch()
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
