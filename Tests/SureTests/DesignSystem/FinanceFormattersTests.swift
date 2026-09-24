import Foundation
import Testing
@testable import Sure

@Suite("Finance formatters")
struct FinanceFormattersTests {
  @Test("Sure-specific currency codes remain visible in full formatting")
  func sureCurrencyCodeFormatting() throws {
    for code in ["BTC", "DOGE", "GBX", "GGP", "IMP", "JEP", "USDC"] {
      let currency = try #require(CurrencyCode(code))
      let formatted = FinanceFormatters.currency(
        Money(minorUnits: currency.minorUnitConversion, currency: currency)
      )

      #expect(formatted.hasPrefix("\(code) "))
    }
  }

  @Test("Sure-specific currency codes remain visible in compact formatting")
  func sureCompactCurrencyCodeFormatting() throws {
    let currency = try #require(CurrencyCode("USDC"))
    let formatted = FinanceFormatters.compactCurrency(
      Money(minorUnits: 1_234_567_800, currency: currency)
    )

    #expect(formatted.hasPrefix("USDC "))
  }

  @Test("Rounds display ties the same way as Sure")
  func sureCompatibleRounding() throws {
    let currency = try #require(CurrencyCode("USD"))
    let locale = Locale(identifier: "en_US")

    #expect(FinanceFormatters.currency(
      DecimalMoney(amount: Decimal(string: "12.345")!, currency: currency),
      locale: locale
    ) == "$12.35")
    #expect(FinanceFormatters.currency(
      DecimalMoney(amount: Decimal(string: "-12.345")!, currency: currency),
      locale: locale
    ) == "-$12.35")
  }

  @Test("Whole-unit headlines round half up and keep Sure currency codes")
  func wholeCurrency() throws {
    let usd = try #require(CurrencyCode("USD"))
    let usdc = try #require(CurrencyCode("USDC"))
    let locale = Locale(identifier: "en_US")

    #expect(FinanceFormatters.wholeCurrency(
      DecimalMoney(amount: Decimal(string: "523.65")!, currency: usd), locale: locale
    ) == "$524")
    #expect(FinanceFormatters.wholeCurrency(
      DecimalMoney(amount: Decimal(string: "212.20")!, currency: usd), locale: locale
    ) == "$212")
    #expect(FinanceFormatters.wholeCurrency(
      DecimalMoney(amount: 0, currency: usd), locale: locale
    ) == "$0")
    #expect(FinanceFormatters.wholeCurrency(
      DecimalMoney(amount: 12, currency: usdc), locale: locale
    ).hasPrefix("USDC "))
  }
}
