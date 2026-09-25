import Foundation

struct FinanceKitHistoryCheckpoint: Codable, Equatable, Sendable {
  var accountToken: Data?
  var balanceTokens: [UUID: Data]
  var transactionTokens: [UUID: Data]

  static var empty: FinanceKitHistoryCheckpoint {
    FinanceKitHistoryCheckpoint(accountToken: nil, balanceTokens: [:], transactionTokens: [:])
  }
}
