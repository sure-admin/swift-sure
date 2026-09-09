import Foundation
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

  @Test("Existing authorization is not presented as an account connection")
  func existingAuthorization() async {
    let account = LocalFinancialAccount(
      id: UUID(),
      name: "Apple Card",
      institutionName: "Goldman Sachs",
      kind: .liability,
      balance: Money(minorUnits: -12_345, currency: CurrencyCode("USD")!)
    )
    let connector = AppleCardConnectorFake(status: .authorized, accounts: [account])
    let store = AppleCardConnectionStore(connector: connector)

    await store.refresh()

    #expect(store.state == .authorized)
    #expect(store.accounts == [account])
    #expect(connector.accountRequestCount == 1)
  }

  @Test("A connection request publishes denial")
  func deniedRequest() async {
    let connector = AppleCardConnectorFake(requestResult: .denied)
    let store = AppleCardConnectionStore(connector: connector)

    await store.connect()

    #expect(store.state == .denied)
    #expect(connector.authorizationRequestCount == 1)
  }

  @Test("Revoked access removes locally displayed accounts")
  func revokedAccess() async {
    let account = LocalFinancialAccount(
      id: UUID(),
      name: "Savings",
      institutionName: "Apple",
      kind: .asset,
      balance: nil
    )
    let connector = AppleCardConnectorFake(status: .authorized, accounts: [account])
    let store = AppleCardConnectionStore(connector: connector)
    await store.refresh()

    connector.status = .denied
    await store.refresh()

    #expect(store.state == .denied)
    #expect(store.accounts.isEmpty)
  }
}

private final class AppleCardConnectorFake: AppleCardConnecting, @unchecked Sendable {
  var isAvailable: Bool
  var status: AppleCardAuthorization
  var requestResult: AppleCardAuthorization
  var accounts: [LocalFinancialAccount]
  var statusRequestCount = 0
  var authorizationRequestCount = 0
  var accountRequestCount = 0

  init(
    isAvailable: Bool = true,
    status: AppleCardAuthorization = .notDetermined,
    requestResult: AppleCardAuthorization = .authorized,
    accounts: [LocalFinancialAccount] = []
  ) {
    self.isAvailable = isAvailable
    self.status = status
    self.requestResult = requestResult
    self.accounts = accounts
  }

  func authorizationStatus() async throws -> AppleCardAuthorization {
    statusRequestCount += 1
    return status
  }

  func requestAuthorization() async throws -> AppleCardAuthorization {
    authorizationRequestCount += 1
    return requestResult
  }

  func fetchAccounts() async throws -> [LocalFinancialAccount] {
    accountRequestCount += 1
    return accounts
  }
}
