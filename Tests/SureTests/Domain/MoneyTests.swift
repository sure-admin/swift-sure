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
    #expect(CurrencyCode("ZZZ") == nil)
    #expect(CurrencyCode("usd")?.rawValue == "USD")
  }

  @Test("Converts exact decimal wire amounts without rounding")
  func decimalAmounts() throws {
    let usd = try #require(CurrencyCode("USD"))
    let kwd = try #require(CurrencyCode("KWD"))

    #expect(
      Money(decimalValue: Decimal(string: "0.00")!, currency: usd)?.minorUnits == 0
    )
    #expect(
      Money(decimalValue: Decimal(string: "999999999.99")!, currency: usd)?.minorUnits
        == 99_999_999_999
    )
    #expect(
      Money(decimalValue: Decimal(string: "12.345")!, currency: kwd)?.minorUnits
        == 12_345
    )
    #expect(Money(decimalValue: Decimal(string: "12.345")!, currency: usd) == nil)
    #expect(
      Money(
        decimalValue: Decimal(string: "92233720368547758.08")!,
        currency: usd
      ) == nil
    )
  }

  @Test("Aggregation separates currencies and reports overflow")
  func aggregation() throws {
    let usd = try #require(CurrencyCode("USD"))
    let eur = try #require(CurrencyCode("EUR"))
    let grouped = MoneyBreakdown(aggregating: [
      Money(minorUnits: 10, currency: usd),
      Money(minorUnits: 20, currency: eur),
      Money(minorUnits: 5, currency: usd)
    ])
    let overflow = MoneyBreakdown(aggregating: [
      Money(minorUnits: Int64.max, currency: usd),
      Money(minorUnits: 1, currency: usd)
    ])

    #expect(grouped.amounts == [
      Money(minorUnits: 20, currency: eur),
      Money(minorUnits: 15, currency: usd)
    ])
    #expect(grouped.isAvailable)
    #expect(!overflow.isAvailable)
  }

  @Test("Empty and single-currency breakdowns retain their availability semantics")
  func emptyAndSingleBreakdowns() throws {
    let usd = try #require(CurrencyCode("USD"))
    let amount = Money(minorUnits: 12_345, currency: usd)
    let empty = MoneyBreakdown(aggregating: [])
    let single = MoneyBreakdown(aggregating: [amount])

    #expect(empty.isAvailable)
    #expect(empty.amounts.isEmpty)
    #expect(empty.singleAmount == nil)
    #expect(single.isAvailable)
    #expect(single.singleAmount == amount)
  }

  @Test("Subtraction requires one currency and rejects integer overflow")
  func subtraction() throws {
    let usd = try #require(CurrencyCode("USD"))
    let eur = try #require(CurrencyCode("EUR"))

    #expect(
      Money(minorUnits: 10_000, currency: usd).subtracting(
        Money(minorUnits: 2_500, currency: usd)
      ) == Money(minorUnits: 7_500, currency: usd)
    )
    #expect(
      Money(minorUnits: 10_000, currency: usd).subtracting(
        Money(minorUnits: 2_500, currency: eur)
      ) == nil
    )
    #expect(
      Money(minorUnits: Int64.min, currency: usd).subtracting(
        Money(minorUnits: 1, currency: usd)
      ) == nil
    )
  }

  @Test("Magnitude rejects the one signed value that cannot be negated")
  func magnitude() throws {
    let usd = try #require(CurrencyCode("USD"))

    #expect(
      Money(minorUnits: -12_345, currency: usd).magnitude
        == Money(minorUnits: 12_345, currency: usd)
    )
    #expect(Money(minorUnits: Int64.min, currency: usd).magnitude == nil)
  }
}
