import Foundation

struct FinanceKitSourceAccount: Codable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable {
    case asset
    case liability
  }

  var sourceID: UUID
  var lineageID: UUID
  var mappingVersion: Int
  var displayName: String
  var institutionName: String
  var accountDescription: String?
  var currency: String
  var kind: Kind
  var openingDate: Date?

  private enum CodingKeys: String, CodingKey {
    case sourceID = "source_id"
    case lineageID = "lineage_id"
    case mappingVersion = "mapping_version"
    case displayName = "display_name"
    case institutionName = "institution_name"
    case accountDescription = "account_description"
    case currency
    case kind
    case openingDate = "opening_date"
  }
}
