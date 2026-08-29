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
    #expect(record.netWorth.amount == Decimal(string: "987654321.09"))
    #expect(record.assets.amount == Decimal(string: "1000000000.10"))
    #expect(record.liabilities.amount == Decimal(string: "12345679.01"))
    let request = try #require(await stub.requests().first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/v1/balance_sheet")
    #expect(request.url?.query == nil)
  }

  @Test("Parses signed exponent-form Rails money without rounding")
  func exponentMoney() throws {
    let money = try APIMoneyDTO(
      amount: "-0.12345e3",
      currency: "USD",
      formatted: "-$123.45"
    ).decimalMoney()

    #expect(money.amount == Decimal(string: "-123.45"))
  }

  @Test("Rejects malformed or overflowing exponent money")
  func invalidExponentMoney() {
    #expect(throws: SureAPIError.decoding) {
      try APIMoneyDTO(
        amount: "0.12e",
        currency: "USD",
        formatted: "$0.12"
      ).decimalMoney()
    }
    #expect(throws: SureAPIError.decoding) {
      try APIMoneyDTO(
        amount: "1e1000",
        currency: "USD",
        formatted: "$1e1000"
      ).decimalMoney()
    }
  }

  @Test("Preserves valid sub-minor-unit FX precision")
  func fxPrecision() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "balance-sheet-fx-precision")
    ])

    let record = try await BalanceSheetAPIClient(
      transport: makeTransport(stub)
    ).fetch()

    #expect(record.netWorth.amount == Decimal(string: "12.345"))
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
