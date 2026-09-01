protocol AppleCardConnecting: Sendable {
  var isAvailable: Bool { get }

  func authorizationStatus() async throws -> AppleCardAuthorization
  func requestAuthorization() async throws -> AppleCardAuthorization
}
