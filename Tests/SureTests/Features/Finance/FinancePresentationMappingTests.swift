import Foundation
import Testing
@testable import Sure

@Suite("Finance presentation mapping")
struct FinancePresentationMappingTests {
  @Test("Preserves signed account balances and currency")
  func accountMapping() throws {
    let identifier = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000901"))
    let currency = try #require(CurrencyCode("EUR"))
    let record = AccountRecord(
      id: identifier,
      name: "Travel Card",
      institutionName: nil,
      accountType: "credit_card",
      classification: "liability",
      status: "active",
      balance: Money(minorUnits: -42_015, currency: currency)
    )

    let first = FinancePresentationMapping.account(from: record)
    let second = FinancePresentationMapping.account(from: record)
    #expect(first.balance == -420.15)
    #expect(first.kind == .credit)
    #expect(first.currencyCode == "EUR")
    #expect(first.tintName == second.tintName)
  }

  @Test("Bridges transaction sign, account, date, and currency without inventing values")
  func transactionMapping() throws {
    let identifier = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000902"))
    let accountID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000901"))
    let currency = try #require(CurrencyCode("KWD"))
    let record = TransactionRecord(
      id: identifier,
      accountID: accountID,
      name: "Card purchase",
      categoryName: "Dining",
      merchantName: "Synthetic Merchant",
      date: try LocalDate(year: 2026, month: 8, day: 28),
      signedAmount: Money(minorUnits: -12_345, currency: currency),
      classification: .expense
    )

    let transaction = FinancePresentationMapping.transaction(from: record)
    #expect(transaction.id == identifier.uuidString.lowercased())
    #expect(transaction.merchant == "Card purchase")
    #expect(transaction.amount == 12.345)
    #expect(transaction.kind == .expense)
    #expect(transaction.accountID == accountID.uuidString.lowercased())
    #expect(transaction.currencyCode == "KWD")
  }
}
