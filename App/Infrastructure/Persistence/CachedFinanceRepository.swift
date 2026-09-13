import Foundation

/// Session policy sits above endpoints; the transport still enforces every network permit.
@MainActor
final class CachedFinanceRepository: RemoteAssistantClient, FinanceDataClient, TransactionHistoryClient, FinancialSummaryProviding, SpendingComparisonClient {
  private let base: any FinanceDataClient
  private let remote: (any RemoteAssistantClient)?
  private let history: any TransactionHistoryClient
  private let summaries: any FinancialSummaryProviding
  private let cache: ServerReadCache
  private let gate: BackendAccessGate
  private let identity: () -> (URL, String)?
  private let now: () -> Date
  private let legacySnapshotURL: URL?
  private let legacyResponsesURL: URL?
  private(set) var metadata: [String: ReadMetadata] = [:]
  private var metadataScope: String?
  private var generation = 0
  private var summaryTasks: [SpendingMonth: Task<FinancialSummary, Error>] = [:]

  init(base: any FinanceDataClient, history: any TransactionHistoryClient,
       summaries: any FinancialSummaryProviding, cache: ServerReadCache, gate: BackendAccessGate,
       identity: @escaping () -> (URL, String)?, now: @escaping () -> Date,
       legacySnapshotURL: URL? = nil, legacyResponsesURL: URL? = nil, remote: (any RemoteAssistantClient)? = nil) {
    self.remote = remote
    self.base = base; self.history = history; self.summaries = summaries
    self.cache = cache; self.gate = gate; self.identity = identity; self.now = now
    self.legacySnapshotURL = legacySnapshotURL; self.legacyResponsesURL = legacyResponsesURL
  }

  func fetchConversations() async throws -> [AssistantConversation] {
    guard let remote else { throw DataFailure.unavailable }
    return try await read(key: "chats", fetch: { try await remote.fetchConversations() },
      encode: { try JSONEncoder().encode($0) }, decode: { try JSONDecoder().decode([AssistantConversation].self, from: $0) })
  }
  func fetchConversation(id: UUID) async throws -> AssistantConversationDetail {
    guard let remote else { throw DataFailure.unavailable }
    return try await read(key: "chat/" + id.uuidString, fetch: { try await remote.fetchConversation(id: id) },
      encode: { try JSONEncoder().encode($0) }, decode: { try JSONDecoder().decode(AssistantConversationDetail.self, from: $0) })
  }
  func createChat(title: String) async throws -> UUID {
    guard let remote else { throw DataFailure.unavailable }
    let permit = try gate.permit()
    let scope = currentScope
    let id = try await remote.createChat(title: title)
    try gate.validate(permit)
    guard scope == currentScope else { throw CancellationError() }
    return id
  }
  func sendMessage(_ content: String, chatID: UUID) async throws -> String {
    guard let remote else { throw DataFailure.unavailable }
    let permit = try gate.permit()
    let scope = currentScope
    let response = try await remote.sendMessage(content, chatID: chatID)
    try gate.validate(permit)
    guard scope == currentScope else { throw CancellationError() }
    return response
  }

  func fetchBalanceSheet() async throws -> BalanceSheetRecord {
    try await resource("balance-sheet", get: { try await base.fetchBalanceSheet() },
      put: { $0.balanceSheet = $1 }, take: { guard let value = $0.balanceSheet else { throw DataFailure.malformed }; return value })
  }
  func fetchAccounts() async throws -> [FinanceAccount] {
    try await resource("accounts", get: { try await base.fetchAccounts() }, put: { $0.accounts = $1 }, take: { $0.accounts })
  }
  func fetchBudgetCategories() async throws -> [BudgetCategory] {
    try await resource("budgets", get: { try await base.fetchBudgetCategories() }, put: { $0.budgets = $1 }, take: { $0.budgets })
  }
  func fetchInsights() async throws -> [BackendInsight] {
    try await resource("insights", get: { try await base.fetchInsights() }, put: { $0.insights = $1 }, take: { $0.insights })
  }
  func fetchTransactions(in dateWindow: TransactionDateWindow) async throws -> [FinanceTransaction] {
    try await fetchTransactions(TransactionHistoryRequest(dateWindow: dateWindow))
  }
  func transactionMetadata(for request: TransactionHistoryRequest) async -> ReadMetadata? { await readMetadata(for: Self.transactionKey(request)) }

  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction] {
    let scope = currentScope
    let generation = self.generation
    let lease = await cache.lease()
    guard scope == currentScope, generation == self.generation else { throw CancellationError() }
    let result = try await resource(Self.transactionKey(request), get: {
      let records = try await history.fetchTransactions(request)
      guard records.allSatisfy({ request.dateWindow.contains($0.date) && (request.accountID == nil || $0.accountID == request.accountID) }) else {
        throw DataFailure.malformed
      }
      return records
    },
      put: { $0.transactions = $1 }, take: { $0.transactions })
    if let scope, let info = metadata[Self.transactionKey(request)], info.source == .server, info.failure == nil {
      let pointer = TransactionWindowPointer(accountID: request.accountID, start: request.startDate, end: request.endDate)
      if let payload = try? JSONEncoder().encode(pointer) {
        try? await cache.write(.init(fetchedAt: info.fetchedAt, payload: payload), scope: scope,
          key: Self.latestWindowKey(request.accountID), lease: lease)
      }
    }
    guard scope == currentScope, generation == self.generation else { throw CancellationError() }
    return result
  }

  func latestDownloadedTransactions(accountID: UUID?) async -> DownloadedTransactionWindow? {
    guard let scope = currentScope else { return nil }
    let generation = self.generation
    guard let pointer = try? await cache.read(scope: scope, key: Self.latestWindowKey(accountID)),
          let window = try? JSONDecoder().decode(TransactionWindowPointer.self, from: pointer.payload),
          window.accountID == accountID,
          let request = try? TransactionHistoryRequest(accountID: accountID,
            dateWindow: TransactionDateWindow(startDate: window.start, endDate: window.end)),
          let entry = try? await cache.read(scope: scope, key: Self.transactionKey(request)),
          let snapshot = try? FinanceDataSnapshotCodec().decode(entry.payload),
          currentScope == scope, self.generation == generation else { return nil }
    return DownloadedTransactionWindow(request: request, transactions: snapshot.transactions,
      metadata: ReadMetadata(fetchedAt: entry.fetchedAt, source: .cache))
  }

  private static func latestWindowKey(_ accountID: UUID?) -> String { "latest-transactions/" + (accountID?.uuidString ?? "all") }
  private struct TransactionWindowPointer: Codable {
    var accountID: UUID?
    var start: LocalDate
    var end: LocalDate
  }

  func fetchSummary(for month: SpendingMonth) async throws -> FinancialSummary {
    if let task = summaryTasks[month] { return try await task.value }
    let request = generation
    let task = Task { @MainActor in
      try await read(key: Self.summaryKey(month), fetch: { try await summaries.fetchSummary(for: month) },
        encode: { try JSONEncoder().encode(FinancialSummaryDTO($0)) },
        decode: { try JSONDecoder().decode(FinancialSummaryDTO.self, from: $0).record() })
    }
    summaryTasks[month] = task
    defer { if request == generation { summaryTasks[month] = nil } }
    return try await task.value
  }
  func comparisonMetadata(for month: SpendingMonth) async -> ReadMetadata? { await readMetadata(for: Self.summaryKey(month)) }

  func fetchComparison(for month: SpendingMonth) async throws -> SpendingComparison {
    try await fetchSummary(for: month).comparison
  }

  func clear() async throws {
    generation &+= 1
    metadataScope = nil
    summaryTasks.values.forEach { $0.cancel() }
    summaryTasks.removeAll()
    metadata.removeAll()
    try await cache.removeAll()
    try await cache.removeLegacyFiles([legacySnapshotURL, legacyResponsesURL].compactMap { $0 })
  }

  func cachedSnapshot() async -> FinanceDataSnapshot? {
    guard let (server, id) = identity() else { return nil }
    let scope = server.absoluteString + "\n" + id
    prepareMetadata(scope)
    let request = generation
    let lease = await cache.lease()
    guard generation == request else { return nil }
    if let legacySnapshotURL { try? await cache.migrateLegacySnapshot(at: legacySnapshotURL, server: server, identity: id, lease: lease) }
    guard currentScope == scope, generation == request else { return nil }
    var snapshot = emptySnapshot(server: server, id: id)
    for key in ["balance-sheet", "accounts", "budgets", "insights", "legacy-preview"] {
      guard let entry = try? await cache.read(scope: scope, key: key),
            let value = try? FinanceDataSnapshotCodec().decode(entry.payload),
            currentScope == scope, generation == request else { continue }
      metadata[key] = ReadMetadata(fetchedAt: entry.fetchedAt, source: .cache)
      switch key {
      case "balance-sheet": snapshot.balanceSheet = value.balanceSheet
      case "accounts": snapshot.accounts = value.accounts
      case "budgets": snapshot.budgets = value.budgets
      case "insights": snapshot.insights = value.insights
      case "legacy-preview": snapshot.transactions = value.transactions
      default: break
      }
    }
    if let downloaded = await latestDownloadedTransactions(accountID: nil) {
      snapshot.transactions = downloaded.transactions
      metadata["legacy-preview"] = downloaded.metadata
    }
    guard currentScope == scope, generation == request, !metadata.isEmpty else { return nil }
    // A composite snapshot cannot claim that every resource has the newest timestamp.
    snapshot.lastUpdated = metadata.values.map(\.fetchedAt).min()
    return snapshot
  }

  func readMetadata(for key: String) async -> ReadMetadata? { metadataScope == currentScope ? metadata[key] : nil }

  private func prepareMetadata(_ scope: String) {
    if metadataScope != scope { metadata.removeAll(); metadataScope = scope }
  }

  static func transactionKey(_ request: TransactionHistoryRequest) -> String {
    "transactions/\(request.accountID?.uuidString ?? "all")/\(request.startDate.iso8601String)/\(request.endDate.iso8601String)"
  }
  static func summaryKey(_ month: SpendingMonth) -> String { "summary/\(month.start.iso8601String)" }

  private var currentScope: String? {
    guard let (server, id) = identity() else { return nil }
    return server.absoluteString + "\n" + id
  }

  private func resource<Value>(_ key: String, get: () async throws -> Value,
      put: (inout FinanceDataSnapshot, Value) -> Void, take: (FinanceDataSnapshot) throws -> Value) async throws -> Value {
    guard let (server, id) = identity() else { throw DataFailure.authentication }
    return try await read(key: key, fetch: get, encode: { value in
      var snapshot = emptySnapshot(server: server, id: id)
      put(&snapshot, value)
      return try FinanceDataSnapshotCodec().encode(snapshot)
    }, decode: { try take(FinanceDataSnapshotCodec().decode($0)) })
  }

  private func read<Value>(key: String, fetch: () async throws -> Value,
      encode: (Value) throws -> Data, decode: (Data) throws -> Value) async throws -> Value {
    guard let scope = currentScope else { throw DataFailure.authentication }
    prepareMetadata(scope)
    let request = generation
    let lease = await cache.lease()
    guard generation == request else { throw CancellationError() }
    do {
      let permit = try gate.permit()
      let value = try await fetch()
      try Task.checkCancellation()
      try gate.validate(permit)
      guard currentScope == scope, generation == request else { throw CancellationError() }
      let fetchedAt = now()
      var storageFailure: DataFailure?
      do {
        try await cache.write(.init(fetchedAt: fetchedAt, payload: encode(value)), scope: scope, key: key, lease: lease)
      } catch is CancellationError { throw CancellationError() }
      catch { storageFailure = .persistence }
      try Task.checkCancellation()
      try gate.validate(permit)
      guard currentScope == scope, generation == request else { throw CancellationError() }
      metadata[key] = ReadMetadata(fetchedAt: fetchedAt, source: .server, failure: storageFailure)
      return value
    } catch {
      let failure = DataFailure(error)
      guard failure.allowsCachedRead else { throw failure }
      guard let entry = try? await cache.read(scope: scope, key: key) else { throw failure }
      let value = try decode(entry.payload)
      try Task.checkCancellation()
      guard currentScope == scope, generation == request else { throw CancellationError() }
      metadata[key] = ReadMetadata(fetchedAt: entry.fetchedAt, source: .cache, failure: failure)
      return value
    }
  }

  private func emptySnapshot(server: URL, id: String) -> FinanceDataSnapshot {
    FinanceDataSnapshot(serverURL: server, connectionIdentity: id, balanceSheet: nil,
      accounts: [], transactions: [], budgets: [], insights: [], lastUpdated: nil)
  }
}
