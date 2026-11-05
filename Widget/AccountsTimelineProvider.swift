import WidgetKit

/// Reads the app's snapshot. The app reloads this widget whenever it writes or
/// removes the snapshot, so the timeline never needs to schedule its own refresh.
struct AccountsTimelineProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> AccountsEntry {
    AccountsEntry(date: .now, snapshot: .placeholder, configuration: AccountsWidgetIntent())
  }

  func snapshot(for configuration: AccountsWidgetIntent, in context: Context) async -> AccountsEntry {
    let saved = AccountsWidgetSnapshotStore.appGroup().load()
    let snapshot = saved ?? (context.isPreview ? .placeholder : nil)
    return AccountsEntry(date: .now, snapshot: snapshot, configuration: configuration)
  }

  func timeline(for configuration: AccountsWidgetIntent, in context: Context) async -> Timeline<AccountsEntry> {
    let entry = AccountsEntry(
      date: .now,
      snapshot: AccountsWidgetSnapshotStore.appGroup().load(),
      configuration: configuration
    )
    return Timeline(entries: [entry], policy: .never)
  }
}

private extension AccountsWidgetSnapshot {
  /// Sample data for the widget gallery only; never shown as real balances.
  static var placeholder: AccountsWidgetSnapshot {
    AccountsWidgetSnapshot(
      accounts: [
        Account(id: "checking", name: String(localized: "Checking"), institution: "", balance: "$2,450.12", isLiability: false),
        Account(id: "savings", name: String(localized: "Savings"), institution: "", balance: "$8,100.00", isLiability: false),
        Account(id: "card", name: String(localized: "Credit Card"), institution: "", balance: "-$412.30", isLiability: true)
      ],
      netWorth: "$10,137.82",
      updatedAt: .now
    )
  }
}
