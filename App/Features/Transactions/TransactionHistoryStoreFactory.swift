import Foundation

@MainActor
final class TransactionHistoryStoreFactory {
  var client: any TransactionHistoryClient
  var calendar: Calendar
  var now: () -> Date

  init(
    client: any TransactionHistoryClient,
    calendar: Calendar,
    now: @escaping () -> Date
  ) {
    self.client = client
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
      calendar: calendar,
      now: now
    )
    stores.removeAll { $0.value == nil }
    stores.append(WeakStore(value: store))
    return store
  }
}
