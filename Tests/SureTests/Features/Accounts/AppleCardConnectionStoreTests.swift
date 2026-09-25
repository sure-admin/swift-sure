import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Apple Card connection")
struct AppleCardConnectionStoreTests {
  @Test("Only explicitly synchronized source identities disappear from the local list")
  func hidesMappedAccountsOnly() async {
    let first = LocalFinancialAccount(id: UUID(), name: "Apple Card", institutionName: "Apple",
      kind: .liability, balance: nil)
    var sameName = first; sameName.id = UUID()
    let store = AppleCardConnectionStore(connector: AppleCardConnectorFake(status: .authorized, accounts: [first, sameName]))
    await store.refresh()
    #expect(store.accounts(excludingSyncedSourceIDs: [first.id]) == [sameName])
    #expect(store.accounts(excludingSyncedSourceIDs: []) == [first, sameName])
    #expect(store.accounts == [first, sameName]) // Local access and sync collection remain available.
  }

  @Test("Wallet approval survives a signed-out cold launch")
  func walletApprovalSurvivesRelaunch() async {
    let account = LocalFinancialAccount(
      id: UUID(), name: "Apple Card", institutionName: "Wallet", kind: .liability, balance: nil
    )
    let connector = AppleCardConnectorFake(status: .authorized, accounts: [account])
    let firstLaunch = AppleCardConnectionStore(connector: connector)
    await firstLaunch.connect()
    let relaunched = AppleCardConnectionStore(connector: connector)
    let lifecycle = ApplicationConnectionLifecycle()
    let publisher = FinanceKitPublisherLifecycleFake()
    lifecycle.financeKitPublisher = publisher
    lifecycle.restoreInitialState(isExplicitlySignedOut: true)
    #expect(publisher.blockBackgroundDeliveryCallCount() == 1)
    await relaunched.refresh()

    #expect(relaunched.state == .authorized)
    #expect(relaunched.accounts == [account])
    #expect(connector.authorizationRequestCount == 1)

    // The stored app decision never overrides revoked system permission.
    connector.status = .denied
    await relaunched.refresh()
    #expect(relaunched.state == .denied)
    #expect(relaunched.accounts.isEmpty)
  }

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

  @Test("Sure login, replacement, failed connection, and logout preserve Wallet access")
  func sureSessionChangesPreserveWallet() async {
    let account = LocalFinancialAccount(
      id: UUID(), name: "Apple Card", institutionName: "Wallet", kind: .liability, balance: nil
    )
    let connector = AppleCardConnectorFake(status: .authorized, accounts: [account])
    let store = AppleCardConnectionStore(connector: connector)
    await store.refresh()
    let lifecycle = ApplicationConnectionLifecycle()
    let publisher = FinanceKitPublisherLifecycleFake()
    lifecycle.financeKitPublisher = publisher
    lifecycle.appleCardConnection = store
    await lifecycle.prepareForConnectionChange()
    await lifecycle.didCommitConnectionChange()
    #expect(store.accounts == [account])
    #expect(store.walletSpendingAccess.isAuthorized)
    await lifecycle.didConnect()
    #expect(store.accounts == [account])
    #expect(store.walletSpendingAccess.isAuthorized)
    await lifecycle.prepareForConnectionChange()
    await lifecycle.didFailConnectionChange()
    #expect(store.accounts == [account])
    await lifecycle.prepareForLogout()
    lifecycle.didLogOut()
    #expect(store.accounts == [account])
    #expect(store.state == .authorized)
    #expect(await publisher.disconnectCallCount() == 2)
    let relaunched = AppleCardConnectionStore(connector: connector)
    await relaunched.refresh()
    #expect(relaunched.accounts == [account])
    #expect(connector.authorizationRequestCount == 0)
  }

  @Test("Temporary refresh errors retain accounts; revoked permission clears them")
  func failedRefreshKeepsAccounts() async {
    let account = LocalFinancialAccount(
      id: UUID(), name: "Apple Card", institutionName: "Wallet", kind: .liability, balance: nil
    )
    let connector = AppleCardConnectorFake(status: .authorized, accounts: [account])
    let store = AppleCardConnectionStore(connector: connector)
    await store.refresh()
    connector.failFetch = true
    await store.refresh()
    #expect(store.accounts == [account])
    guard case .failed = store.state else { Issue.record("Expected refresh failure"); return }
    connector.status = .denied
    await store.refresh()
    #expect(store.accounts.isEmpty)
    #expect(!store.walletSpendingAccess.isAuthorized)
  }

  @Test("Fresh local Wallet access loads Card and Cash without a Sure session or subscription")
  func cardAndCashWithoutSure() async {
    let accounts = [
      LocalFinancialAccount(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        name: "Apple Card", institutionName: "Wallet", kind: .liability, balance: nil
      ),
      LocalFinancialAccount(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
        name: "Apple Cash", institutionName: "Wallet", kind: .asset, balance: nil
      )
    ]
    let connector = AppleCardConnectorFake(accounts: accounts)
    let store = AppleCardConnectionStore(connector: connector)
    await store.refresh()
    #expect(store.state == .ready)
    #expect(store.accounts.isEmpty)
    await store.connect()
    #expect(store.state == .authorized)
    #expect(store.accounts == accounts)
    #expect(store.walletSpendingAccess.isAuthorized)
    #expect(connector.authorizationRequestCount == 1)
    #expect(connector.accountRequestCount == 1)
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

private actor FinanceKitPublisherLifecycleFake: FinanceKitPublisherLifecycleHandling {
  private nonisolated let blockingCalls = FinanceKitBlockingCallCounter()
  private var disconnectCalls = 0

  func install(configuration: FinanceKitPublisherConfiguration, credential: String) async throws { }
  nonisolated func blockBackgroundDelivery() { blockingCalls.increment() }
  func configuredConnectionID() async -> UUID? { nil }
  func renewCredential() async throws { }
  func repair() async throws { }
  func resumeIfConfigured() async { }
  func suspend() async { }
  func disconnect() async throws { disconnectCalls += 1 }
  nonisolated func blockBackgroundDeliveryCallCount() -> Int { blockingCalls.value }
  func disconnectCallCount() -> Int { disconnectCalls }
}

private final class FinanceKitBlockingCallCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int { lock.withLock { count } }
  func increment() { lock.withLock { count += 1 } }
}

private final class AppleCardConnectorFake: AppleCardConnecting, @unchecked Sendable {
  var isAvailable: Bool
  var status: AppleCardAuthorization
  var requestResult: AppleCardAuthorization
  var accounts: [LocalFinancialAccount]
  var statusRequestCount = 0
  var authorizationRequestCount = 0
  var accountRequestCount = 0
  var failFetch = false

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
    if failFetch { throw DataFailure.offline }
    return accounts
  }
}
