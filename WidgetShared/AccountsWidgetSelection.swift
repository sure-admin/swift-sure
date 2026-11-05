import Foundation

/// Decides which snapshot accounts a widget shows.
enum AccountsWidgetSelection {
  /// With no picked IDs, every account: assets before liabilities, keeping
  /// Sure's order within each group. With picked IDs, exactly
  /// those accounts in the picked order; IDs no longer in the snapshot are skipped.
  static func accounts(
    in snapshot: AccountsWidgetSnapshot,
    pickedIDs: [String]
  ) -> [AccountsWidgetSnapshot.Account] {
    guard !pickedIDs.isEmpty else {
      let assets = snapshot.accounts.filter { !$0.isLiability }
      let liabilities = snapshot.accounts.filter(\.isLiability)
      return assets + liabilities
    }
    var byID: [String: AccountsWidgetSnapshot.Account] = [:]
    for account in snapshot.accounts where byID[account.id] == nil {
      byID[account.id] = account
    }
    var seen = Set<String>()
    return pickedIDs.compactMap { id in
      guard seen.insert(id).inserted else { return nil }
      return byID[id]
    }
  }
}
