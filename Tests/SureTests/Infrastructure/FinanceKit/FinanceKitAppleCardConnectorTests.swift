import Testing
@testable import Sure

@Suite("FinanceKit Apple Card connector")
struct FinanceKitAppleCardConnectorTests {
  @Test("Builds without FinanceKit enabled stay unavailable")
  func disabledBuildUnavailable() async throws {
    let connector = FinanceKitAppleCardConnector()

    #expect(connector.isAvailable == false)
    #expect(try await connector.authorizationStatus() == .denied)
    #expect(try await connector.requestAuthorization() == .denied)
  }
}
