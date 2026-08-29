import Foundation

enum StoredAuthenticatedSession: Codable, Equatable, Sendable {
  case oauth(StoredOAuthSession)
  case apiKey(StoredAPIKeySession)

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .oauth:
      self = .oauth(try container.decode(StoredOAuthSession.self, forKey: .oauth))
    case .apiKey:
      self = .apiKey(try container.decode(StoredAPIKeySession.self, forKey: .apiKey))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .oauth(let session):
      try container.encode(Kind.oauth, forKey: .kind)
      try container.encode(session, forKey: .oauth)
    case .apiKey(let session):
      try container.encode(Kind.apiKey, forKey: .kind)
      try container.encode(session, forKey: .apiKey)
    }
  }

  private enum CodingKeys: CodingKey {
    case kind
    case oauth
    case apiKey
  }

  private enum Kind: String, Codable {
    case oauth
    case apiKey
  }
}
