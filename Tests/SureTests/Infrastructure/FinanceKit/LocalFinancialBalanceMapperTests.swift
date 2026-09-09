import Foundation
import Testing
@testable import Sure

@Suite("Local financial balance mapping")
struct LocalFinancialBalanceMapperTests {
  @Test("Credits are positive and debits are negative")
  func direction() throws {
    let mapper = LocalFinancialBalanceMapper()

    let credit = try mapper.map(amount: 123.45, currencyCode: "GBP", direction: .credit)
    let debit = try mapper.map(amount: 123.45, currencyCode: "GBP", direction: .debit)

    #expect(credit == Money(minorUnits: 12_345, currency: CurrencyCode("GBP")!))
    #expect(debit == Money(minorUnits: -12_345, currency: CurrencyCode("GBP")!))
  }

  @Test("A signed source amount is normalized exactly once")
  func signedSourceAmount() throws {
    let mapper = LocalFinancialBalanceMapper()

    let debit = try mapper.map(amount: -42, currencyCode: "USD", direction: .debit)

    #expect(debit == Money(minorUnits: -4_200, currency: CurrencyCode("USD")!))
  }

  @Test("Unknown currencies fail instead of receiving an invented scale")
  func unknownCurrency() {
    let mapper = LocalFinancialBalanceMapper()

    #expect(throws: LocalFinancialBalanceMapper.MappingError.unsupportedCurrency("ZZZ")) {
      try mapper.map(amount: 1, currencyCode: "ZZZ", direction: .credit)
    }
  }
}
