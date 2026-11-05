import AppIntents
import WidgetKit

/// The options under "Edit Widget".
struct AccountsWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Account Balances"
  static let description = IntentDescription("Shows balances from Sure's last account update.")

  /// Empty shows every account; otherwise exactly the picked ones, in the picked order.
  @Parameter(title: "Accounts", description: "Leave empty to show all accounts.")
  var accounts: [WidgetAccountEntity]?

  @Parameter(title: "Show Net Worth", default: true)
  var showNetWorth: Bool
}
