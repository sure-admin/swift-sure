import Foundation

struct FinanceKitSourceMoney: Codable, Equatable, Sendable {
  enum Direction: String, Codable, Sendable {
    case credit
    case debit
  }

  var amount: String
  var currency: String
  var direction: Direction
}
