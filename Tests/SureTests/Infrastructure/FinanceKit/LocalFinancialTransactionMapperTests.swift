import Foundation
import Testing
@testable import Sure

@Suite("Local financial transaction mapping")
struct LocalFinancialTransactionMapperTests {
  @Test("Wallet MCCs remain separate from transaction categories", arguments: [Int16(5411), 742, 9999, nil])
  func merchantCategoryCode(code: Int16?) throws {
    let transaction = try LocalFinancialTransactionMapper().map(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
      accountID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
      merchantName: "Fixture merchant",
      description: "CARD PURCHASE",
      category: "Purchase",
      date: Date(timeIntervalSince1970: 1_700_000_000),
      amount: 12,
      currencyCode: "USD",
      isCredit: false,
      calendar: utcCalendar,
      merchantCategoryCode: code
    )

    #expect(transaction.merchantCategoryCode == code)
    #expect(transaction.category == "Purchase")
    let expected: String? = switch code {
    case 5411: "5411"
    case 742: "0742"
    case 9999: "9999"
    default: nil
    }
    #expect(transaction.formattedMerchantCategoryCode == expected)
  }

  @Test("Debit transactions become expenses with positive stored magnitudes")
  func debit() throws {
    let amount = try #require(Decimal(string: "12.34"))
    let transaction = try LocalFinancialTransactionMapper().map(
      id: UUID(),
      accountID: UUID(),
      merchantName: "Corner Shop",
      description: "CARD PURCHASE",
      category: "Purchase",
      date: Date(timeIntervalSince1970: 1_700_000_000),
      amount: amount,
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
    let amount = try #require(Decimal(string: "4.56"))
    let transaction = try LocalFinancialTransactionMapper().map(
      id: UUID(),
      accountID: UUID(),
      merchantName: nil,
      description: "INTEREST PAYMENT",
      category: "Interest",
      date: Date(timeIntervalSince1970: 1_700_000_000),
      amount: -amount,
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
