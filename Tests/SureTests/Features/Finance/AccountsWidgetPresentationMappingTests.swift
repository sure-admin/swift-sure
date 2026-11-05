import Foundation
import Testing
@testable import Sure

@Suite("Accounts widget presentation mapping")
struct AccountsWidgetPresentationMappingTests {
  private let locale = Locale(identifier: "en_US")
  private let usd = CurrencyCode("USD")!

  @Test("Accounts keep their Sure ID, name, institution and Accounts-screen balance")
  func assetMapping() throws {
    let update = AccountsWidgetUpdate(accounts: [testReadAccount], netWorth: nil, updatedAt: testReadDate)
    let snapshot = AccountsWidgetPresentationMapping.snapshot(for: update, locale: locale)
    let account = try #require(snapshot.accounts.first)
    #expect(snapshot.accounts.count == 1)
    #expect(account.id == testReadAccount.id.uuidString)
    #expect(account.name == "Checking")
    #expect(account.institution == "Test")
    #expect(account.balance == FinanceFormatters.currency(testReadAccount.displayBalance, locale: locale))
    #expect(!account.isLiability)
    #expect(snapshot.updatedAt == testReadDate)
    #expect(snapshot.version == AccountsWidgetSnapshot.currentVersion)
  }

  @Test("Liabilities are flagged and shown with the Accounts screen's inverted sign")
  func liabilitySign() {
    let card = FinanceAccount(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
      name: "Card", institution: "Bank", kind: .credit,
      balance: Money(minorUnits: 41230, currency: usd), tintName: "red", isLiability: true)
    let snapshot = AccountsWidgetPresentationMapping.snapshot(
      for: AccountsWidgetUpdate(accounts: [card], netWorth: nil, updatedAt: testReadDate), locale: locale)
    let expected = FinanceFormatters.currency(DecimalMoney(amount: Decimal(string: "-412.3")!, currency: usd), locale: locale)
    #expect(snapshot.accounts.first?.isLiability == true)
    #expect(snapshot.accounts.first?.balance == expected)
  }

  @Test("A credit account without an explicit classification counts as a liability")
  func creditFallback() {
    let card = FinanceAccount(id: UUID(), name: "Card", institution: "Bank", kind: .credit,
      balance: Money(minorUnits: 100, currency: usd), tintName: "red")
    let snapshot = AccountsWidgetPresentationMapping.snapshot(
      for: AccountsWidgetUpdate(accounts: [card], netWorth: nil, updatedAt: testReadDate), locale: locale)
    #expect(snapshot.accounts.first?.isLiability == true)
  }

  @Test("Wallet-sourced accounts use the Apple Wallet institution label")
  func walletInstitution() {
    var account = testReadAccount
    account.walletSourceAccountID = UUID()
    let snapshot = AccountsWidgetPresentationMapping.snapshot(
      for: AccountsWidgetUpdate(accounts: [account], netWorth: nil, updatedAt: testReadDate), locale: locale)
    #expect(snapshot.accounts.first?.institution == "Apple Wallet")
  }

  @Test("Net worth comes only from the balance sheet and is omitted when unavailable")
  func netWorth() {
    let money = DecimalMoney(amount: Decimal(string: "1234.56")!, currency: usd)
    let withNetWorth = AccountsWidgetPresentationMapping.snapshot(
      for: AccountsWidgetUpdate(accounts: [], netWorth: money, updatedAt: testReadDate), locale: locale)
    let without = AccountsWidgetPresentationMapping.snapshot(
      for: AccountsWidgetUpdate(accounts: [], netWorth: nil, updatedAt: testReadDate), locale: locale)
    #expect(withNetWorth.netWorth == FinanceFormatters.currency(money, locale: locale))
    #expect(without.netWorth == nil)
  }
}
