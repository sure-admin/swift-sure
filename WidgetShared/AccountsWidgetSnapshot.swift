import Foundation

/// The home screen widget's copy of the Sure account list.
///
/// The app writes it after a complete Sure accounts read and removes it when the
/// session disconnects. The widget only reads this file: it never contacts the
/// server, never receives credentials, and so stays behind the app's
/// authentication and subscription boundaries.
struct AccountsWidgetSnapshot: Codable, Equatable, Sendable {
  /// Bumped when the stored shape changes; older files are ignored, not migrated.
  static let currentVersion = 1
  static let widgetKind = "SureAccounts"

  struct Account: Codable, Equatable, Sendable, Identifiable {
    /// The Sure account ID.
    var id: String
    var name: String
    var institution: String
    /// Formatted by the app with the same rules as the Accounts screen, so the
    /// widget needs no currency logic of its own.
    var balance: String
    var isLiability: Bool
  }

  var version: Int
  var accounts: [Account]
  /// The server's balance-sheet net worth, formatted; nil when it isn't loaded.
  var netWorth: String?
  /// When Sure last returned the account list.
  var updatedAt: Date

  init(version: Int = Self.currentVersion, accounts: [Account], netWorth: String?, updatedAt: Date) {
    self.version = version
    self.accounts = accounts
    self.netWorth = netWorth
    self.updatedAt = updatedAt
  }
}
