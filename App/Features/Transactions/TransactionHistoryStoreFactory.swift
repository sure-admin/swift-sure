import Foundation

@MainActor
struct TransactionHistoryStoreFactory {
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

  func makeStore(for scope: TransactionHistoryScope) -> TransactionHistoryStore {
    TransactionHistoryStore(
      scope: scope,
      client: client,
      calendar: calendar,
      now: now
    )
  }
}
