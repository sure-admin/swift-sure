import Foundation
import Testing
@testable import Sure

@Suite("Local financial transaction mapping")
struct LocalFinancialTransactionMapperTests {
  @Test("Debit transactions become expenses with positive stored magnitudes")
  func debit() throws {
    let transaction = try LocalFinancialTransactionMapper().map(
      id: UUID(),
      accountID: UUID(),
      merchantName: "Corner Shop",
      description: "CARD PURCHASE",
      category: "Purchase",
      date: Date(timeIntervalSince1970: 1_700_000_000),
      amount: 12.34,
      currencyCode: "GBP",
      isCredit: false,
      calendar: utcCalendar
    )

    #expect(transaction.merchant == "Corner Shop")
    #expect(transaction.kind == .expense)
    #expect(transaction.amount == Money(minorUnits: 1_234, currency: CurrencyCode("GBP")!))
    #expect(transaction.signedAmount.minorUnits == -1_234)
  }

  @Test("Credits become income and descriptions replace missing merchants")
  func credit() throws {
    let transaction = try LocalFinancialTransactionMapper().map(
      id: UUID(),
      accountID: UUID(),
      merchantName: nil,
      description: "INTEREST PAYMENT",
      category: "Interest",
      date: Date(timeIntervalSince1970: 1_700_000_000),
      amount: -4.56,
      currencyCode: "USD",
      isCredit: true,
      calendar: utcCalendar
    )

    #expect(transaction.merchant == "INTEREST PAYMENT")
    #expect(transaction.kind == .income)
    #expect(transaction.signedAmount.minorUnits == 456)
  }

  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}
