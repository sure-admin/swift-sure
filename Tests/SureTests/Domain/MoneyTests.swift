import Foundation
import Testing
@testable import Sure

@Suite("Money")
struct MoneyTests {
  @Test("Preserves signed minor units for currencies with different scales")
  func currencyScales() throws {
    let usd = try #require(CurrencyCode("USD"))
    let jpy = try #require(CurrencyCode("JPY"))
    let kwd = try #require(CurrencyCode("KWD"))
    let clf = try #require(CurrencyCode("CLF"))

    #expect(Money(minorUnits: -12_345, currency: usd).decimalValue == Decimal(string: "-123.45"))
    #expect(Money(minorUnits: 0, currency: usd).decimalValue == Decimal.zero)
    #expect(Money(minorUnits: 12_345, currency: jpy).decimalValue == Decimal(12_345))
    #expect(Money(minorUnits: 12_345, currency: kwd).decimalValue == Decimal(string: "12.345"))
    #expect(Money(minorUnits: 12_345, currency: clf).decimalValue == Decimal(string: "1.2345"))
    #expect(
      Money(minorUnits: Int64.max, currency: usd).decimalValue
        == Decimal(Int64.max) / Decimal(100)
    )
  }

  @Test("Rejects values that are not three-letter ASCII currency codes")
  func invalidCurrencyCodes() {
    #expect(CurrencyCode("US") == nil)
    #expect(CurrencyCode("US1") == nil)
    #expect(CurrencyCode("ÅBC") == nil)
    #expect(CurrencyCode("usd")?.rawValue == "USD")
  }
}
