#if os(iOS) && FINANCEKIT_ENABLED
import Foundation
import FinanceKit

struct FinanceKitAppleCardConnector: AppleCardConnecting {
  var isAvailable: Bool {
    #if targetEnvironment(simulator)
    false
    #else
    FinanceStore.isDataAvailable(.financialData)
    #endif
  }

  func authorizationStatus() async throws -> AppleCardAuthorization {
    #if targetEnvironment(simulator)
    return .denied
    #else
    return try await map(FinanceStore.shared.authorizationStatus())
    #endif
  }

  func requestAuthorization() async throws -> AppleCardAuthorization {
    #if targetEnvironment(simulator)
    return .denied
    #else
    return try await map(FinanceStore.shared.requestAuthorization())
    #endif
  }

  func fetchAccounts() async throws -> [LocalFinancialAccount] {
    #if targetEnvironment(simulator)
    return []
    #else
    return try await loadAccounts()
    #endif
  }

  private func loadAccounts() async throws -> [LocalFinancialAccount] {
    let store = FinanceStore.shared
    async let accounts = store.accounts(query: AccountQuery())
    async let balances = store.accountBalances(query: AccountBalanceQuery())
    let result = try await (accounts, balances)
    return try map(accounts: result.0, balances: result.1)
  }

  private func map(_ status: AuthorizationStatus) -> AppleCardAuthorization {
    switch status {
    case .notDetermined: .notDetermined
    case .authorized: .authorized
    case .denied: .denied
    @unknown default: .denied
    }
  }


  private func map(
    accounts: [Account],
    balances: [AccountBalance]
  ) throws -> [LocalFinancialAccount] {
    let latestBalances = Dictionary(grouping: balances, by: \.accountID)
      .compactMapValues { records in
        records.max { balanceDate($0) < balanceDate($1) }
      }

    return try accounts.map { account in
      LocalFinancialAccount(
        id: account.id,
        name: account.displayName,
        institutionName: account.institutionName,
        kind: account.assetAccount == nil ? .liability : .asset,
        balance: try latestBalances[account.id].map(mapBalance)
      )
    }
    .sorted { lhs, rhs in
      let institutionOrder = lhs.institutionName.localizedCaseInsensitiveCompare(rhs.institutionName)
      if institutionOrder == .orderedSame {
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      return institutionOrder == .orderedAscending
    }
  }

  private func mapBalance(_ accountBalance: AccountBalance) throws -> Money {
    let balance: Balance
    switch accountBalance.currentBalance {
    case .available(let available):
      balance = available
    case .availableAndBooked(_, let booked):
      balance = booked
    case .booked(let booked):
      balance = booked
    }

    return try LocalFinancialBalanceMapper().map(
      amount: balance.amount.amount,
      currencyCode: balance.amount.currencyCode,
      direction: balance.creditDebitIndicator == .credit ? .credit : .debit
    )
  }

  private func balanceDate(_ accountBalance: AccountBalance) -> Date {
    switch accountBalance.currentBalance {
    case .available(let available): available.asOfDate
    case .availableAndBooked(_, let booked): booked.asOfDate
    case .booked(let booked): booked.asOfDate
    }
  }
}
#else
struct FinanceKitAppleCardConnector: AppleCardConnecting {
  var isAvailable: Bool { false }

  func authorizationStatus() async throws -> AppleCardAuthorization { .denied }
  func requestAuthorization() async throws -> AppleCardAuthorization { .denied }
  func fetchAccounts() async throws -> [LocalFinancialAccount] { [] }
}
#endif
