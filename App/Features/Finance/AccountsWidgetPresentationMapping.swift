import Foundation

/// Formats a finance update for the widget with the Accounts screen's rules, so
/// the widget shows the same signs, currencies and institution labels.
enum AccountsWidgetPresentationMapping {
  static func snapshot(
    for update: AccountsWidgetUpdate,
    locale: Locale = .autoupdatingCurrent
  ) -> AccountsWidgetSnapshot {
    AccountsWidgetSnapshot(
      accounts: update.accounts.map { account in
        AccountsWidgetSnapshot.Account(
          id: account.id.uuidString,
          name: account.name,
          institution: account.displayInstitution,
          balance: FinanceFormatters.currency(account.displayBalance, locale: locale),
          isLiability: account.isLiability ?? (account.kind == .credit)
        )
      },
      netWorth: update.netWorth.map { FinanceFormatters.currency($0, locale: locale) },
      updatedAt: update.updatedAt
    )
  }
}
