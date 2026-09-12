import Foundation

#if os(iOS) && FINANCEKIT_ENABLED
import FinanceKit

struct FinanceKitAppleCardConnector: AppleCardConnecting, TransactionHistoryClient, WalletSpendingTransactionProviding {
  var calendar: Calendar = .autoupdatingCurrent
  var store: FinanceStore = .shared

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
    return try await map(store.authorizationStatus())
    #endif
  }

  func requestAuthorization() async throws -> AppleCardAuthorization {
    #if targetEnvironment(simulator)
    return .denied
    #else
    return try await map(store.requestAuthorization())
    #endif
  }

  func fetchAccounts() async throws -> [LocalFinancialAccount] {
    #if targetEnvironment(simulator)
    return []
    #else
    return try await loadAccounts()
    #endif
  }

  func fetchTransactions(
    _ request: TransactionHistoryRequest
  ) async throws -> [FinanceTransaction] {
    #if targetEnvironment(simulator)
    return []
    #else
    return try await loadTransactions(request)
    #endif
  }

  func fetchSpendingTransactions(
    in window: TransactionDateWindow, accountIDs: Set<UUID>
  ) async throws -> [WalletSpendingTransaction] {
    #if targetEnvironment(simulator)
    throw SpendingComparisonServiceError.unavailable
    #else
    guard try await authorizationStatus() == .authorized else {
      throw SpendingComparisonServiceError.unavailable
    }
    // A nil limit requests the complete local snapshot; no first-page totals.
    let records = try await store.transactions(query: FinanceKit.TransactionQuery(limit: nil))
    return try records.filter {
      let date = try LocalDate($0.postedDate ?? $0.transactionDate, in: calendar)
      return accountIDs.contains($0.accountID) && window.contains(date)
    }.map { transaction in
      let signed = try LocalFinancialBalanceMapper().map(
        amount: transaction.transactionAmount.amount,
        currencyCode: transaction.transactionAmount.currencyCode,
        direction: .credit
      )
      return WalletSpendingTransaction(
        id: transaction.id, accountID: transaction.accountID,
        date: try LocalDate(transaction.postedDate ?? transaction.transactionDate, in: calendar),
        amount: signed, isPosted: transaction.status == .booked,
        isDebit: transaction.creditDebitIndicator == .debit,
        isTransfer: transaction.transactionType == .transfer
      )
    }
    #endif
  }

  private func loadTransactions(
    _ request: TransactionHistoryRequest
  ) async throws -> [FinanceTransaction] {
    guard let accountID = request.accountID else { return [] }
    let query = FinanceKit.TransactionQuery()
    return try await store.transactions(query: query)
      .filter {
        let date = try LocalDate(
          $0.postedDate ?? $0.transactionDate,
          in: calendar
        )
        return isDisplayable($0.status)
          && $0.accountID == accountID
          && request.dateWindow.contains(date)
      }
      .map(mapTransaction)
  }

  private func loadAccounts() async throws -> [LocalFinancialAccount] {
    // An unfiltered query includes every shared institution, not just Apple products.
    // A missing balance must not hide an account that can provide transactions.
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
    @unknown default:
      throw FinanceKitConnectorError.unsupportedBalance
    }

    return try LocalFinancialBalanceMapper().map(
      amount: balance.amount.amount,
      currencyCode: balance.amount.currencyCode,
      direction: balance.creditDebitIndicator == .credit ? .credit : .debit
    )
  }

  private func mapTransaction(_ transaction: Transaction) throws -> FinanceTransaction {
    try LocalFinancialTransactionMapper().map(
      id: transaction.id,
      accountID: transaction.accountID,
      merchantName: transaction.merchantName,
      description: transaction.transactionDescription,
      category: categoryName(transaction.transactionType),
      date: transaction.postedDate ?? transaction.transactionDate,
      amount: transaction.transactionAmount.amount,
      currencyCode: transaction.transactionAmount.currencyCode,
      isCredit: transaction.creditDebitIndicator == .credit,
      calendar: calendar
    )
  }

  private func categoryName(_ type: TransactionType) -> String {
    switch type {
    case .adjustment: "Adjustment"
    case .atm: "ATM"
    case .billPayment: "Bill Payment"
    case .check: "Check"
    case .deposit: "Deposit"
    case .directDebit: "Direct Debit"
    case .directDeposit: "Direct Deposit"
    case .dividend: "Dividend"
    case .fee: "Fee"
    case .interest: "Interest"
    case .loan: "Loan"
    case .pointOfSale: "Purchase"
    case .refund: "Refund"
    case .standingOrder: "Standing Order"
    case .transfer: "Transfer"
    case .unknown: "Uncategorized"
    case .withdrawal: "Withdrawal"
    @unknown default: "Uncategorized"
    }
  }

  private func isDisplayable(_ status: TransactionStatus) -> Bool {
    switch status {
    case .authorized, .booked, .pending: true
    case .memo, .rejected: false
    @unknown default: false
    }
  }

  private func balanceDate(_ accountBalance: AccountBalance) -> Date {
    switch accountBalance.currentBalance {
    case .available(let available): available.asOfDate
    case .availableAndBooked(_, let booked): booked.asOfDate
    case .booked(let booked): booked.asOfDate
    @unknown default: .distantPast
    }
  }
}

private enum FinanceKitConnectorError: Error {
  case unsupportedBalance
}
#else
struct FinanceKitAppleCardConnector: AppleCardConnecting, TransactionHistoryClient, WalletSpendingTransactionProviding {
  var calendar: Calendar = .autoupdatingCurrent

  func fetchSpendingTransactions(
    in window: TransactionDateWindow, accountIDs: Set<UUID>
  ) async throws -> [WalletSpendingTransaction] {
    throw SpendingComparisonServiceError.unavailable
  }

  var isAvailable: Bool { false }

  func authorizationStatus() async throws -> AppleCardAuthorization { .denied }
  func requestAuthorization() async throws -> AppleCardAuthorization { .denied }
  func fetchAccounts() async throws -> [LocalFinancialAccount] { [] }
  func fetchTransactions(
    _ request: TransactionHistoryRequest
  ) async throws -> [FinanceTransaction] {
    []
  }
}
#endif
