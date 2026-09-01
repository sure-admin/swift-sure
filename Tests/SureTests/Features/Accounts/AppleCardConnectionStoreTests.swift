import Testing
@testable import Sure

@MainActor
@Suite("Apple Card connection")
struct AppleCardConnectionStoreTests {
  @Test("Unavailable devices don't request authorization")
  func unavailable() async {
    let connector = AppleCardConnectorFake(isAvailable: false)
    let store = AppleCardConnectionStore(connector: connector)

    await store.refresh()

    #expect(store.state == .unavailable)
    #expect(connector.statusRequestCount == 0)
  }

  @Test("Existing authorization appears connected")
  func existingAuthorization() async {
    let connector = AppleCardConnectorFake(status: .authorized)
    let store = AppleCardConnectionStore(connector: connector)

    await store.refresh()

    #expect(store.state == .connected)
  }

  @Test("A connection request publishes denial")
  func deniedRequest() async {
    let connector = AppleCardConnectorFake(requestResult: .denied)
    let store = AppleCardConnectionStore(connector: connector)

    await store.connect()

    #expect(store.state == .denied)
    #expect(connector.authorizationRequestCount == 1)
  }
}

private final class AppleCardConnectorFake: AppleCardConnecting, @unchecked Sendable {
  var isAvailable: Bool
  var status: AppleCardAuthorization
  var requestResult: AppleCardAuthorization
  var statusRequestCount = 0
  var authorizationRequestCount = 0

  init(
    isAvailable: Bool = true,
    status: AppleCardAuthorization = .notDetermined,
    requestResult: AppleCardAuthorization = .authorized
  ) {
    self.isAvailable = isAvailable
    self.status = status
    self.requestResult = requestResult
  }

  func authorizationStatus() async throws -> AppleCardAuthorization {
    statusRequestCount += 1
    return status
  }

  func requestAuthorization() async throws -> AppleCardAuthorization {
    authorizationRequestCount += 1
    return requestResult
  }
}
