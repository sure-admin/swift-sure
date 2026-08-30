import Foundation

enum OAuthTokenSource: Codable, Equatable, Sendable {
  case dynamicClient
  case mobileDevice(deviceID: String)

  private enum CodingKeys: CodingKey {
    case kind
    case deviceID
  }

  private enum Kind: String, Codable {
    case dynamicClient
    case mobileDevice
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .dynamicClient:
      self = .dynamicClient
    case .mobileDevice:
      self = .mobileDevice(
        deviceID: try container.decode(String.self, forKey: .deviceID)
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .dynamicClient:
      try container.encode(Kind.dynamicClient, forKey: .kind)
    case .mobileDevice(let deviceID):
      try container.encode(Kind.mobileDevice, forKey: .kind)
      try container.encode(deviceID, forKey: .deviceID)
    }
  }
}
