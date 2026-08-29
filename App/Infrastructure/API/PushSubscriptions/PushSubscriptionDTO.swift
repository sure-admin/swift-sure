import Foundation

struct PushSubscriptionDTO: Decodable {
  var id: UUID
  var environment: APNsEnvironment
  var platform: Platform
  var lastRegisteredAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case environment
    case platform
    case lastRegisteredAt = "last_registered_at"
  }

  enum Platform: String, Codable {
    case iOS = "ios"
  }
}
