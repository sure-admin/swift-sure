import AppIntents

/// Offers the accounts from the app's last snapshot, so the picker works offline
/// and never needs a Sure session of its own.
struct WidgetAccountQuery: EntityQuery {
  func entities(for identifiers: [WidgetAccountEntity.ID]) async throws -> [WidgetAccountEntity] {
    let known = Self.accounts()
    return identifiers.map { id in
      // Keep a picked account that's no longer in Sure visible in the picker, so
      // the choice isn't silently lost; the widget simply has nothing to show for it.
      known.first { $0.id == id } ?? WidgetAccountEntity(
        id: id,
        name: String(localized: "Unavailable Account"),
        detail: String(localized: "Not in Sure's last update")
      )
    }
  }

  func suggestedEntities() async throws -> [WidgetAccountEntity] {
    Self.accounts()
  }

  private static func accounts() -> [WidgetAccountEntity] {
    let accounts = AccountsWidgetSnapshotStore.appGroup().load()?.accounts ?? []
    return accounts
      .sorted { lhs, rhs in
        if lhs.isLiability != rhs.isLiability { return !lhs.isLiability }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
      .map { WidgetAccountEntity(account: $0) }
  }
}
