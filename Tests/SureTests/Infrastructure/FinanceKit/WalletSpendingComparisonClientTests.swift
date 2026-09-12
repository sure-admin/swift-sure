import Foundation
import Testing
@testable import Sure

@Suite("Wallet spending client")
struct WalletSpendingComparisonClientTests {
  @Test("Requests the complete previous month through today's cutoff")
  func dateWindow() async throws {
    let provider = WalletTransactionProviderStub()
    let client = makeClient(provider)
    let month = SpendingMonth(containing: try LocalDate(year: 2026, month: 9, day: 1))
    let result = try await client.fetchComparison(for: month, access: access)
    let window = try #require(await provider.window)
    #expect(window.startDate.iso8601String == "2026-08-01")
    #expect(window.endDate.iso8601String == "2026-09-11")
    #expect(await provider.accountIDs == access.accountIDs)
    #expect(result.isEmpty)
  }

  @Test("Requires explicit authorized Wallet access before requesting transactions")
  func authorizationGate() async throws {
    let provider = WalletTransactionProviderStub()
    let client = makeClient(provider)
    var denied = access; denied.isAuthorized = false
    do {
      _ = try await client.fetchComparison(for: SpendingMonth(containing: LocalDate(year: 2026, month: 9, day: 1)), access: denied)
      Issue.record("Expected authorization failure")
    } catch WalletSpendingComparisonBuilder.Failure.noAccounts { }
    #expect(await provider.window == nil)
  }

  private var access: WalletSpendingAccess {
    .init(isAuthorized: true, accountIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!], currencies: [CurrencyCode("USD")!], generation: 0)
  }

  private func makeClient(_ provider: WalletTransactionProviderStub) -> WalletSpendingComparisonClient {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11))!
    return WalletSpendingComparisonClient(transactions: provider, calendar: calendar, now: { today })
  }
}

private actor WalletTransactionProviderStub: WalletSpendingTransactionProviding {
  private(set) var window: TransactionDateWindow?
  private(set) var accountIDs: Set<UUID> = []

  func fetchSpendingTransactions(in window: TransactionDateWindow, accountIDs: Set<UUID>) async throws -> [WalletSpendingTransaction] {
    self.window = window
    self.accountIDs = accountIDs
    return []
  }
}
