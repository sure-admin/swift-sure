import Foundation

#if os(iOS) && FINANCEKIT_ENABLED
import FinanceKit

struct FinanceKitHistoryChangeCollector: FinanceKitChangeCollecting {
  var store: FinanceStore = .shared
  var now: @Sendable () -> Date = { Date() }
  private var decimalEncoder = FinanceKitDecimalEncoder()

  func collect(
    configuration: FinanceKitPublisherConfiguration,
    checkpoint encodedCheckpoint: Data?,
    changedTypes: Set<FinanceKitBackgroundDataType>
  ) async throws -> FinanceKitCollectedChanges {
    let isSnapshot = encodedCheckpoint == nil
    var checkpoint = try decodeCheckpoint(encodedCheckpoint)
    let bindings = Dictionary(uniqueKeysWithValues: configuration.accountBindings.map {
      ($0.sourceAccountID, $0)
    })
    var events: [FinanceKitSourceEvent] = []

    if shouldCollect(.accounts, hints: changedTypes, isSnapshot: isSnapshot) {
      let token = try decodeToken(checkpoint.accountToken)
      let changes = try await aggregate(store.accountHistory(since: token, isMonitoring: false))
      for account in coalesced(changes.inserted, changes.updated) {
        guard let binding = bindings[account.id] else { continue }
        events.append(.accountUpsert(try map(account, binding: binding)))
      }
      for accountID in changes.deleted {
        guard let binding = bindings[accountID] else { continue }
        events.append(.accountUnavailable(
          sourceAccountID: accountID,
          lineageID: binding.lineageID,
          mappingVersion: binding.mappingVersion
        ))
      }
      if let token = changes.newToken { checkpoint.accountToken = try encodeToken(token) }
    }

    for binding in configuration.accountBindings {
      if shouldCollect(.accountBalances, hints: changedTypes, isSnapshot: isSnapshot) {
        let token = try decodeToken(checkpoint.balanceTokens[binding.sourceAccountID])
        let changes = try await aggregate(store.accountBalanceHistory(
          forAccountID: binding.sourceAccountID,
          since: token,
          isMonitoring: false
        ))
        for balance in coalesced(changes.inserted, changes.updated) {
          events.append(contentsOf: try map(balance, binding: binding).map(FinanceKitSourceEvent.balanceUpsert))
        }
        if let token = changes.newToken {
          checkpoint.balanceTokens[binding.sourceAccountID] = try encodeToken(token)
        }
      }

      if shouldCollect(.transactions, hints: changedTypes, isSnapshot: isSnapshot) {
        let token = try decodeToken(checkpoint.transactionTokens[binding.sourceAccountID])
        let changes = try await aggregate(store.transactionHistory(
          forAccountID: binding.sourceAccountID,
          since: token,
          isMonitoring: false
        ))
        for transaction in coalesced(changes.inserted, changes.updated) {
          events.append(.transactionUpsert(try map(transaction, binding: binding)))
        }
        for sourceID in changes.deleted {
          events.append(.transactionTombstone(FinanceKitSourceTransactionTombstone(
            sourceID: sourceID,
            sourceAccountID: binding.sourceAccountID,
            lineageID: binding.lineageID,
            mappingVersion: binding.mappingVersion
          )))
        }
        if let token = changes.newToken {
          checkpoint.transactionTokens[binding.sourceAccountID] = try encodeToken(token)
        }
      }
    }

    return FinanceKitCollectedChanges(
      mode: isSnapshot ? .snapshot : .delta,
      capturedAt: now(),
      events: events,
      nextCheckpoint: try JSONEncoder().encode(checkpoint)
    )
  }

  private func shouldCollect(
    _ type: FinanceKitBackgroundDataType,
    hints: Set<FinanceKitBackgroundDataType>,
    isSnapshot: Bool
  ) -> Bool {
    isSnapshot || hints.isEmpty || hints.contains(type)
  }

  private func decodeCheckpoint(_ data: Data?) throws -> FinanceKitHistoryCheckpoint {
    guard let data else { return .empty }
    do { return try JSONDecoder().decode(FinanceKitHistoryCheckpoint.self, from: data) }
    catch { throw FinanceKitSyncError.invalidCheckpoint }
  }

  private func decodeToken(_ data: Data?) throws -> FinanceStore.HistoryToken? {
    guard let data else { return nil }
    do { return try JSONDecoder().decode(FinanceStore.HistoryToken.self, from: data) }
    catch { throw FinanceKitSyncError.invalidCheckpoint }
  }

  private func encodeToken(_ token: FinanceStore.HistoryToken) throws -> Data {
    try JSONEncoder().encode(token)
  }

  private func aggregate<Model>(
    _ history: FinanceStore.History<Model>
  ) async throws -> AggregatedFinanceKitChanges<Model> where Model: Identifiable & Sendable, Model.ID: Hashable & Sendable {
    var result = AggregatedFinanceKitChanges<Model>()
    do {
      for try await changes in history {
        result.inserted.append(contentsOf: changes.inserted)
        result.updated.append(contentsOf: changes.updated)
        result.deleted.append(contentsOf: changes.deleted)
        result.newToken = changes.newToken
      }
      return result
    } catch let error as FinanceError where error == .historyTokenInvalid {
      throw FinanceKitSyncError.historyTokenInvalid
    }
  }

  private func coalesced<Model>(_ inserted: [Model], _ updated: [Model]) -> [Model]
  where Model: Identifiable, Model.ID: Hashable {
    var records: [Model.ID: Model] = [:]
    for record in inserted { records[record.id] = record }
    for record in updated { records[record.id] = record }
    return records.values.sorted { String(describing: $0.id) < String(describing: $1.id) }
  }

  private func map(_ account: Account, binding: FinanceKitAccountBinding) throws -> FinanceKitSourceAccount {
    let kind: FinanceKitSourceAccount.Kind
    switch account {
    case .asset: kind = .asset
    case .liability: kind = .liability
    @unknown default: throw FinanceKitSyncError.unsupportedSourceValue
    }
    return FinanceKitSourceAccount(
      sourceID: account.id,
      lineageID: binding.lineageID,
      mappingVersion: binding.mappingVersion,
      displayName: account.displayName,
      institutionName: account.institutionName,
      accountDescription: account.accountDescription,
      currency: account.currencyCode,
      kind: kind,
      openingDate: account.openingDate
    )
  }

  private func map(
    _ accountBalance: AccountBalance,
    binding: FinanceKitAccountBinding
  ) throws -> [FinanceKitSourceBalance] {
    switch accountBalance.currentBalance {
    case .available(let available):
      return [try map(available, kind: .available, sourceID: accountBalance.id, binding: binding)]
    case .booked(let booked):
      return [try map(booked, kind: .booked, sourceID: accountBalance.id, binding: binding)]
    case .availableAndBooked(let available, let booked):
      return [
        try map(available, kind: .available, sourceID: accountBalance.id, binding: binding),
        try map(booked, kind: .booked, sourceID: accountBalance.id, binding: binding)
      ]
    @unknown default:
      throw FinanceKitSyncError.unsupportedSourceValue
    }
  }

  private func map(
    _ balance: Balance,
    kind: FinanceKitSourceBalance.Kind,
    sourceID: UUID,
    binding: FinanceKitAccountBinding
  ) throws -> FinanceKitSourceBalance {
    FinanceKitSourceBalance(
      sourceID: sourceID,
      sourceAccountID: binding.sourceAccountID,
      lineageID: binding.lineageID,
      mappingVersion: binding.mappingVersion,
      kind: kind,
      observedAt: balance.asOfDate,
      money: try decimalEncoder.money(
        amount: balance.amount.amount,
        currency: balance.amount.currencyCode,
        direction: try direction(balance.creditDebitIndicator)
      )
    )
  }

  private func map(
    _ transaction: Transaction,
    binding: FinanceKitAccountBinding
  ) throws -> FinanceKitSourceTransaction {
    let transactionDirection = try direction(transaction.creditDebitIndicator)
    return FinanceKitSourceTransaction(
      sourceID: transaction.id,
      sourceAccountID: binding.sourceAccountID,
      lineageID: binding.lineageID,
      mappingVersion: binding.mappingVersion,
      amount: try decimalEncoder.money(
        amount: transaction.transactionAmount.amount,
        currency: transaction.transactionAmount.currencyCode,
        direction: transactionDirection
      ),
      foreignAmount: try transaction.foreignCurrencyAmount.map {
        try decimalEncoder.money(
          amount: $0.amount,
          currency: $0.currencyCode,
          direction: transactionDirection
        )
      },
      foreignExchangeRate: try transaction.foreignCurrencyExchangeRate.map(decimalEncoder.exchangeRate),
      transactionDescription: transaction.transactionDescription,
      originalTransactionDescription: transaction.originalTransactionDescription,
      merchantName: transaction.merchantName,
      merchantCategoryCode: transaction.merchantCategoryCode?.rawValue,
      transactionType: transactionType(transaction.transactionType),
      status: status(transaction.status),
      transactedAt: transaction.transactionDate,
      postedAt: transaction.postedDate
    )
  }

  private func direction(_ indicator: CreditDebitIndicator) throws -> FinanceKitSourceMoney.Direction {
    switch indicator {
    case .credit: .credit
    case .debit: .debit
    @unknown default: throw FinanceKitSyncError.unsupportedSourceValue
    }
  }

  private func status(_ value: TransactionStatus) -> String {
    switch value {
    case .authorized: "authorized"
    case .memo: "memo"
    case .pending: "pending"
    case .booked: "booked"
    case .rejected: "rejected"
    @unknown default: "unknown"
    }
  }

  private func transactionType(_ value: TransactionType) -> String {
    switch value {
    case .unknown: "unknown"
    case .adjustment: "adjustment"
    case .atm: "atm"
    case .billPayment: "bill_payment"
    case .check: "check"
    case .deposit: "deposit"
    case .directDeposit: "direct_deposit"
    case .dividend: "dividend"
    case .fee: "fee"
    case .interest: "interest"
    case .pointOfSale: "point_of_sale"
    case .transfer: "transfer"
    case .withdrawal: "withdrawal"
    case .standingOrder: "standing_order"
    case .directDebit: "direct_debit"
    case .loan: "loan"
    case .refund: "refund"
    @unknown default: "unknown"
    }
  }
}

private struct AggregatedFinanceKitChanges<Model: Identifiable> where Model.ID: Hashable {
  var inserted: [Model] = []
  var updated: [Model] = []
  var deleted: [Model.ID] = []
  var newToken: FinanceStore.HistoryToken?
}
#else
struct FinanceKitHistoryChangeCollector: FinanceKitChangeCollecting {
  func collect(
    configuration: FinanceKitPublisherConfiguration,
    checkpoint: Data?,
    changedTypes: Set<FinanceKitBackgroundDataType>
  ) async throws -> FinanceKitCollectedChanges {
    throw FinanceKitSyncError.invalidState
  }
}
#endif
