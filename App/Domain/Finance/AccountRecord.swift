import Foundation

struct AccountRecord: Equatable, Sendable {
  var id: UUID
  var name: String
  var institutionName: String?
  var accountType: String?
  var classification: String
  var status: String
  var balance: Money
}
