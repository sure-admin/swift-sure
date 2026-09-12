import Foundation
import Testing
@testable import Sure

@Suite("Wallet spending comparison")
struct WalletSpendingComparisonBuilderTests {
  private let account = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  private let other = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  private var month: SpendingMonth { SpendingMonth(containing: try! LocalDate(year: 2026, month: 9, day: 1)) }
  private var access: WalletSpendingAccess {
    .init(isAuthorized: true, accountIDs: [account], currencies: [CurrencyCode("USD")!], generation: 0)
  }

  @Test("Uses only posted debits, excluding transfers and unshared accounts")
  func filtering() throws {
    var pending = try entry(2, day: 2); pending.isPosted = false
    var credit = try entry(3, day: 3); credit.isDebit = false
    var transfer = try entry(4, day: 4); transfer.isTransfer = true
    var unshared = try entry(5, day: 5); unshared.accountID = other
    let result = try build([entry(1, day: 1), pending, credit, transfer, unshared, entry(6, day: 12)])
    #expect(result.currentTotal == 10)
    #expect(result.current.count == 11)
    #expect(result.current.allSatisfy { $0.amount == 10 })
  }

  @Test("Aggregates both months and compares the same elapsed days")
  func twoMonths() throws {
    var prior = try entry(2, day: 2); prior.date = try LocalDate(year: 2026, month: 8, day: 2)
    var late = try entry(3, day: 3); late.date = try LocalDate(year: 2026, month: 8, day: 31)
    let result = try build([entry(1, day: 1), prior, late])
    #expect(result.currentTotal == 10)
    #expect(result.previousTotal == 10)
    #expect(result.previous.last?.amount == 20)
    #expect(result.previousPlot.last?.date.day == 31)
    #expect(result.delta == 0)
  }

  @Test("Empty authorized accounts yield zero in their known currency")
  func empty() throws { #expect(try build([]).isEmpty) }

  @Test("Refuses mixed currencies and duplicated transactions")
  func invalidCollections() throws {
    let first = try entry(1, day: 1)
    #expect(throws: WalletSpendingComparisonBuilder.Failure.self) { try build([first, first]) }
    var foreign = try entry(2, day: 2); foreign.amount = Money(minorUnits: 1000, currency: CurrencyCode("EUR")!)
    #expect(throws: WalletSpendingComparisonBuilder.Failure.self) { try build([first, foreign]) }
  }

  @Test("Does not invent a currency or zero total without accounts")
  func unavailable() throws {
    var unknown = access; unknown.currencies = []
    #expect(throws: WalletSpendingComparisonBuilder.Failure.self) { try build([], access: unknown) }
    var empty = access; empty.accountIDs = []
    #expect(throws: WalletSpendingComparisonBuilder.Failure.self) { try build([], access: empty) }
    var denied = access; denied.isAuthorized = false
    #expect(throws: WalletSpendingComparisonBuilder.Failure.self) { try build([], access: denied) }
    #expect(try build([entry(1, day: 1)], access: unknown).currentTotal == 10)
  }

  @Test("Preserves precision while summing beyond Int64 capacity")
  func precision() throws {
    var first = try entry(1, day: 1)
    first.amount = Money(minorUnits: Int64.max, currency: CurrencyCode("KWD")!)
    var second = first; second.id = other
    var kwd = access; kwd.currencies = [CurrencyCode("KWD")!]
    let result = try build([first, second], access: kwd)
    #expect(result.currentTotal == first.amount.decimalValue * 2)
  }

  private func entry(_ id: Int, day: Int) throws -> WalletSpendingTransaction {
    .init(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!, accountID: account,
          date: try month.date(day: day), amount: Money(minorUnits: 1000, currency: CurrencyCode("USD")!),
          isPosted: true, isDebit: true, isTransfer: false)
  }

  private func build(_ transactions: [WalletSpendingTransaction], access: WalletSpendingAccess? = nil) throws -> SpendingComparison {
    try WalletSpendingComparisonBuilder().build(month: month, asOf: month.date(day: 11), access: access ?? self.access, transactions: transactions)
  }
}
