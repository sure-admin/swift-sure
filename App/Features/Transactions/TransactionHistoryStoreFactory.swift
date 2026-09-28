import Foundation

@MainActor
final class TransactionHistoryStoreFactory {
  var client: any TransactionHistoryClient
  private let diagnostics: (any DiagnosticsLogging)?
  private let diagnosticSource: DiagnosticTransactionSource
  var isOffline: () -> Bool
  var calendar: Calendar
  var now: () -> Date

  init(
    client: any TransactionHistoryClient,
    diagnostics: (any DiagnosticsLogging)? = nil,
    diagnosticSource: DiagnosticTransactionSource = .sure,
    isOffline: @escaping () -> Bool = { false },
    calendar: Calendar,
    now: @escaping () -> Date
  ) {
    self.client = client
    self.diagnostics = diagnostics
    self.diagnosticSource = diagnosticSource
    self.isOffline = isOffline
    self.calendar = calendar
    self.now = now
  }

  private var stores: [WeakStore] = []

  func invalidateStores() {
    stores.forEach { $0.value?.invalidate() }
    stores = []
  }

  private struct WeakStore {
    weak var value: TransactionHistoryStore?
  }

  func makeStore(for scope: TransactionHistoryScope) -> TransactionHistoryStore {
    let store = TransactionHistoryStore(
      scope: scope,
      client: client,
      diagnostics: diagnostics,
      diagnosticSource: diagnosticSource,
      isOffline: isOffline,
      calendar: calendar,
      now: now
    )
    stores.removeAll { $0.value == nil }
    stores.append(WeakStore(value: store))
    return store
  }
}
