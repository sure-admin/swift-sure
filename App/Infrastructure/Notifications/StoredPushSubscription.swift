import Foundation

struct StoredPushSubscription: Codable, Equatable, Sendable {
  var id: UUID
  var serverURL: URL
  var deviceToken: String
  var environment: APNsEnvironment

  init(
    id: UUID,
    serverURL: URL,
    deviceToken: String,
    environment: APNsEnvironment
  ) throws {
    guard !deviceToken.isEmpty else {
      throw StoredPushSubscriptionError.invalidDeviceToken
    }

    self.id = id
    self.serverURL = try SureRequestContext(
      baseURL: serverURL,
      authorization: nil
    ).baseURL
    self.deviceToken = deviceToken
    self.environment = environment
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        id: values.decode(UUID.self, forKey: .id),
        serverURL: values.decode(URL.self, forKey: .serverURL),
        deviceToken: values.decode(String.self, forKey: .deviceToken),
        environment: values.decode(APNsEnvironment.self, forKey: .environment)
      )
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .serverURL,
        in: values,
        debugDescription: "The stored push subscription is invalid."
      )
    }
  }
}

private enum StoredPushSubscriptionError: Error {
  case invalidDeviceToken
}
