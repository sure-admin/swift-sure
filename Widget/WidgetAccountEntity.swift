import AppIntents

/// An account offered by the "Accounts" option under "Edit Widget".
struct WidgetAccountEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
  static let defaultQuery = WidgetAccountQuery()

  let id: String
  let name: String
  /// Institution and balance, so accounts with the same name can be told apart.
  let detail: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
  }

  init(id: String, name: String, detail: String) {
    self.id = id
    self.name = name
    self.detail = detail
  }

  init(account: AccountsWidgetSnapshot.Account) {
    let detail = [account.institution, account.balance].filter { !$0.isEmpty }.joined(separator: " · ")
    self.init(id: account.id, name: account.name, detail: detail)
  }
}
