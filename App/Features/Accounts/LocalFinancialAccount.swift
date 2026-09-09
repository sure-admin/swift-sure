import Foundation

struct LocalFinancialAccount: Equatable, Identifiable, Sendable {
  enum Kind: Equatable, Sendable {
    case asset
    case liability
  }

  var id: UUID
  var name: String
  var institutionName: String
  var kind: Kind
  var balance: Money?
}
