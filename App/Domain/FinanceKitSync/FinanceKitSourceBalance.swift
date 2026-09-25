import Foundation

struct FinanceKitSourceBalance: Codable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable {
    case available
    case booked
  }

  var sourceID: UUID
  var sourceAccountID: UUID
  var lineageID: UUID
  var mappingVersion: Int
  var kind: Kind
  var observedAt: Date
  var money: FinanceKitSourceMoney

  private enum CodingKeys: String, CodingKey {
    case sourceID = "source_id"
    case sourceAccountID = "source_account_id"
    case lineageID = "lineage_id"
    case mappingVersion = "mapping_version"
    case kind
    case observedAt = "observed_at"
    case money
  }
}
