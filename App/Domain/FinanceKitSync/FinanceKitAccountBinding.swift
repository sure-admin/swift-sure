import Foundation

struct FinanceKitAccountBinding: Codable, Equatable, Sendable {
  var sourceAccountID: UUID
  var lineageID: UUID
  var mappingVersion: Int

  init(sourceAccountID: UUID, lineageID: UUID, mappingVersion: Int) throws {
    guard mappingVersion > 0 else {
      throw FinanceKitPublisherConfigurationError.invalidMapping
    }
    self.sourceAccountID = sourceAccountID
    self.lineageID = lineageID
    self.mappingVersion = mappingVersion
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      sourceAccountID: container.decode(UUID.self, forKey: .sourceAccountID),
      lineageID: container.decode(UUID.self, forKey: .lineageID),
      mappingVersion: container.decode(Int.self, forKey: .mappingVersion)
    )
  }
}
