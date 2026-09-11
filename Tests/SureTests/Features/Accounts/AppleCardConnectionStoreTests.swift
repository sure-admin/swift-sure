import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Apple Card connection")
struct AppleCardConnectionStoreTests {
  @Test("Newly shared accounts from other institutions appear on refresh")
  func discoversOtherInstitutions() async {
    let card = LocalFinancialAccount(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
      name: "Apple Card", institutionName: "Goldman Sachs", kind: .liability, balance: nil
    )
    let bank = LocalFinancialAccount(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
      name: "Current Account", institutionName: "Monzo", kind: .asset, balance: nil
    )
    let credit = LocalFinancialAccount(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
      name: "Credit Card", institutionName: "Barclaycard", kind: .liability, balance: nil
    )
    let connector = AppleCardConnectorFake(status: .authorized, accounts: [card])
    let store = AppleCardConnectionStore(connector: connector)
    await store.refresh()

    connector.accounts = [card, bank, credit]
    await store.refresh()

    #expect(store.accounts == [card, bank, credit])
    #expect(connector.authorizationRequestCount == 0)
    #expect(connector.accountRequestCount == 2)

    connector.accounts = [bank, credit]
    await store.refresh()
    #expect(store.accounts == [bank, credit])
  }

  @Test("A Wallet response arriving after logout is discarded")
  func lateWalletResponse() async {
    let gate = WalletRequestGate()
    let connector = AppleCardConnectorFake(status: .authorized, accounts: [
      LocalFinancialAccount(id: UUID(), name: "Old account", institutionName: "Wallet", kind: .asset, balance: nil)
    ])
    connector.beforeFetch = { await gate.suspend() }
    let store = AppleCardConnectionStore(connector: connector)
    let request = Task { await store.refresh() }
    await gate.waitUntilStarted()
    store.disconnect()
    await gate.complete()
    await request.value
    #expect(store.accounts.isEmpty)
    #expect(store.state == .ready)
  }

  @Test("Logout clears Wallet data and requires an explicit reconnect")
  func logout() async {
    let account = LocalFinancialAccount(
      id: UUID(), name: "Apple Card", institutionName: "Wallet", kind: .liability, balance: nil
    )
    let connector = AppleCardConnectorFake(status: .authorized, accounts: [account])
    var requiresReconnect = false
    let store = AppleCardConnectionStore(connector: connector, setRequiresReconnect: { requiresReconnect = $0 })
    await store.refresh()
    let lifecycle = ApplicationConnectionLifecycle()
    lifecycle.appleCardConnection = store
    await lifecycle.prepareForLogout()
    #expect(store.accounts.isEmpty)
    #expect(store.state == .ready)
    #expect(requiresReconnect)
    let relaunched = AppleCardConnectionStore(connector: connector, requiresReconnect: requiresReconnect)
    #expect(relaunched.state == .ready)
    await relaunched.refresh()
    #expect(relaunched.accounts.isEmpty)
    #expect(connector.accountRequestCount == 1)
    await store.connect()
    #expect(store.accounts == [account])
    #expect(!requiresReconnect)
  }

  @Test("Available Wallet devices can enter Accounts without Sure credentials")
  func localAvailability() {
    #expect(AppleCardConnectionStore(connector: AppleCardConnectorFake()).isAvailable)
    #expect(!AppleCardConnectionStore(connector: AppleCardConnectorFake(isAvailable: false)).isAvailable)
  }

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
  var beforeFetch: (@Sendable () async -> Void)?

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
    await beforeFetch?()
    return accounts
  }
}

private actor WalletRequestGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func suspend() async {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      waiters.forEach { $0.resume() }
      waiters = []
    }
  }

  func waitUntilStarted() async {
    guard continuation == nil else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func complete() {
    continuation?.resume()
    continuation = nil
  }
}
