import Foundation

struct TransactionRecord: Equatable, Sendable {
  var id: UUID
  var accountID: UUID
  var name: String
  var categoryName: String?
  var merchantName: String?
  var date: LocalDate
  var signedAmount: Money
  var classification: TransactionClassification
}
