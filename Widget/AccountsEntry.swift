import WidgetKit

struct AccountsEntry: TimelineEntry {
  let date: Date
  /// Nil when the app hasn't shared any accounts (not connected, or logged out).
  let snapshot: AccountsWidgetSnapshot?
  let configuration: AccountsWidgetIntent

  var accounts: [AccountsWidgetSnapshot.Account] {
    guard let snapshot else { return [] }
    let picked = configuration.accounts?.map(\.id) ?? []
    return AccountsWidgetSelection.accounts(in: snapshot, pickedIDs: picked)
  }

  var netWorth: String? {
    configuration.showNetWorth ? snapshot?.netWorth : nil
  }
}
