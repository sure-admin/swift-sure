import Foundation

struct FinanceKitSourceTransactionTombstone: Codable, Equatable, Sendable {
  var sourceID: UUID
  var sourceAccountID: UUID
  var lineageID: UUID
  var mappingVersion: Int

  private enum CodingKeys: String, CodingKey {
    case sourceID = "source_id"
    case sourceAccountID = "source_account_id"
    case lineageID = "lineage_id"
    case mappingVersion = "mapping_version"
  }
}
