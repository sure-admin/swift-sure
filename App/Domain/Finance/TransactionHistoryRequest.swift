import Foundation

struct TransactionHistoryRequest: Equatable, Sendable {
  let accountID: UUID?
  let dateWindow: TransactionDateWindow

  init(accountID: UUID? = nil, dateWindow: TransactionDateWindow) {
    self.accountID = accountID
    self.dateWindow = dateWindow
  }

  var startDate: LocalDate { dateWindow.startDate }
  var endDate: LocalDate { dateWindow.endDate }
}
