#if os(iOS) && targetEnvironment(simulator)
import Testing
@testable import Sure

@Suite("FinanceKit Apple Card connector")
struct FinanceKitAppleCardConnectorTests {
  @Test("The simulator is treated as unavailable without calling FinanceKit")
  func simulatorUnavailable() async throws {
    let connector = FinanceKitAppleCardConnector()

    #expect(connector.isAvailable == false)
    #expect(try await connector.authorizationStatus() == .denied)
    #expect(try await connector.requestAuthorization() == .denied)
  }
}
#endif
