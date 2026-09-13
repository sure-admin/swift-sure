import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Application connection lifecycle")
struct ApplicationConnectionLifecycleTests {
  @Test("A verified API-key connection loads every shared finance resource")
  func apiKeyConnectionLoadsFinanceData() async throws {
    let serverURL = try #require(URL(string: "https://sure.example"))
    let credentials = LifecycleCredentialRepository()
    let preferences = LifecycleConnectionPreferences(serverURL: serverURL.absoluteString)
    let session = SureSession(context: nil)
    let lifecycle = ApplicationConnectionLifecycle()
    var offlineClearCount = 0
    lifecycle.clearOfflineResponses = { offlineClearCount += 1 }
    let connection = SureConnection(
      initialState: SureConnectionInitialState(
        serverURL: serverURL.absoluteString,
        credentials: StoredCredentialSnapshot(session: nil),
        isExplicitlySignedOut: false,
        requestContext: nil,
        initializationError: nil
      ),
      session: session,
      credentials: credentials,
      preferences: preferences,
      oauth: LifecycleOAuthStub(),
      mobileSSO: UnavailableMobileSSOAuthenticator(),
      verify: { context in
        #expect(context.baseURL == serverURL)
        #expect(context.authorization == .apiKey("valid-key"))
      },
      beginCredentialChange: { },
      endCredentialChange: { },
      lifecycle: lifecycle,
      accessGate: entitledTestGate()
    )
    let expectedContext = try SureRequestContext(
      baseURL: serverURL,
      authorization: .apiKey("valid-key")
    )
    let client = LifecycleFinanceDataClient(
      session: session,
      expectedContext: expectedContext
    )
    let financeData = FinanceDataStore(
      connection: connection,
      client: client,
      calendar: Calendar(identifier: .gregorian),
      now: { Date(timeIntervalSince1970: 1_800_000_000) },
      syncInsights: { _ in }
    )
    let notifications = LifecycleNotificationSpy()
    lifecycle.financeData = financeData
    lifecycle.notificationLifecycle = notifications
    connection.apiKey = "valid-key"

    await connection.connectWithAPIKey()

    #expect(offlineClearCount == 1)
    #expect(connection.status == .connected)
    #expect(financeData.state == .loaded)
    #expect(financeData.balanceSheet != nil)
    #expect(financeData.accounts.map(\.id) == [lifecycleID(1)])
    #expect(financeData.transactions.map(\.id) == [lifecycleID(2)])
    #expect(financeData.budgets.map(\.id) == [lifecycleID(3)])
    #expect(financeData.insights.map(\.id) == ["insight-1"])
    let calls = await client.recordedCalls()
    #expect(calls.count == LifecycleFinanceCall.allCases.count)
    for call in LifecycleFinanceCall.allCases {
      #expect(calls.filter { $0 == call }.count == 1)
    }
    #expect(notifications.didConnectCount == 1)

    await connection.logOut()

    #expect(offlineClearCount == 2)
    #expect(financeData.insights.isEmpty)
    #expect(financeData.accounts.isEmpty)
    #expect(financeData.transactions.isEmpty)
    #expect(financeData.budgets.isEmpty)
    #expect(financeData.balanceSheet == nil)
    #expect(!connection.isConfigured)
    #expect(connection.email.isEmpty)
    #expect(connection.password.isEmpty)
  }

  @Test("Cancellation after cleanup restores the prior session data")
  func cancelledAPIKeyChangeRestoresFinanceData() async throws {
    let oldSession = try StoredAPIKeySession(
      serverURL: #require(URL(string: "https://old.sure.example")),
      apiKey: "old-key",
      isVerified: true
    )
    let oldContext = try oldSession.requestContext()
    let snapshot = StoredCredentialSnapshot(session: .apiKey(oldSession))
    let credentials = LifecycleCredentialRepository(snapshot: snapshot)
    let preferences = LifecycleConnectionPreferences(
      serverURL: oldSession.serverURL.absoluteString
    )
    let session = SureSession(context: oldContext)
    let lifecycle = ApplicationConnectionLifecycle()
    var offlineClearCount = 0
    lifecycle.clearOfflineResponses = { offlineClearCount += 1 }
    let gate = LifecycleCredentialChangeGate()
    let connection = SureConnection(
      initialState: SureConnectionInitialState(
        serverURL: oldSession.serverURL.absoluteString,
        credentials: snapshot,
        isExplicitlySignedOut: false,
        requestContext: oldContext,
        initializationError: nil
      ),
      session: session,
      credentials: credentials,
      preferences: preferences,
      oauth: LifecycleOAuthStub(),
      mobileSSO: UnavailableMobileSSOAuthenticator(),
      verify: { _ in },
      beginCredentialChange: { await gate.begin() },
      endCredentialChange: { gate.end() },
      lifecycle: lifecycle,
      accessGate: entitledTestGate()
    )
    let client = LifecycleFinanceDataClient(
      session: session,
      expectedContext: oldContext
    )
    let financeData = makeFinanceData(connection: connection, client: client)
    let notifications = LifecycleNotificationSpy()
    lifecycle.financeData = financeData
    lifecycle.notificationLifecycle = notifications
    connection.serverURL = "https://new.sure.example"
    connection.apiKey = "candidate-key"

    let connectionTask = Task { @MainActor in
      await connection.connectWithAPIKey()
    }
    await gate.waitUntilStarted()
    connectionTask.cancel()
    gate.resume()
    await connectionTask.value

    #expect(connection.status == .connected)
    #expect(offlineClearCount == 0)
    #expect(try await session.requestContext() == oldContext)
    #expect(financeData.state == .loaded)
    #expect(financeData.accounts.map(\.id) == [lifecycleID(1)])
    #expect(await client.recordedCalls().count == LifecycleFinanceCall.allCases.count)
    #expect(notifications.didConnectCount == 1)
  }

  @Test("API-key persistence failure restores the prior session data")
  func apiKeyPersistenceFailureRestoresFinanceData() async throws {
    let oldSession = try StoredAPIKeySession(
      serverURL: #require(URL(string: "https://old.sure.example")),
      apiKey: "old-key",
      isVerified: true
    )
    let oldContext = try oldSession.requestContext()
    let snapshot = StoredCredentialSnapshot(session: .apiKey(oldSession))
    let credentials = LifecycleCredentialRepository(snapshot: snapshot)
    credentials.failNextReplace = true
    let session = SureSession(context: oldContext)
    let lifecycle = ApplicationConnectionLifecycle()
    var offlineClearCount = 0
    lifecycle.clearOfflineResponses = { offlineClearCount += 1 }
    let connection = SureConnection(
      initialState: SureConnectionInitialState(
        serverURL: oldSession.serverURL.absoluteString,
        credentials: snapshot,
        isExplicitlySignedOut: false,
        requestContext: oldContext,
        initializationError: nil
      ),
      session: session,
      credentials: credentials,
      preferences: LifecycleConnectionPreferences(
        serverURL: oldSession.serverURL.absoluteString
      ),
      oauth: LifecycleOAuthStub(),
      mobileSSO: UnavailableMobileSSOAuthenticator(),
      verify: { _ in },
      beginCredentialChange: { },
      endCredentialChange: { },
      lifecycle: lifecycle,
      accessGate: entitledTestGate()
    )
    let client = LifecycleFinanceDataClient(
      session: session,
      expectedContext: oldContext
    )
    let financeData = makeFinanceData(connection: connection, client: client)
    lifecycle.financeData = financeData
    connection.serverURL = "https://new.sure.example"
    connection.apiKey = "candidate-key"

    await connection.connectWithAPIKey()

    #expect(connection.isConfigured)
    #expect(connection.status == .failed("The Sure connection couldn’t be completed."))
    #expect(offlineClearCount == 0)
    #expect(try await session.requestContext() == oldContext)
    #expect(try credentials.loadCredentials() == snapshot)
    #expect(financeData.state == .loaded)
    #expect(financeData.accounts.map(\.id) == [lifecycleID(1)])
    let calls = await client.recordedCalls()
    #expect(calls.count == LifecycleFinanceCall.allCases.count)
    for call in LifecycleFinanceCall.allCases {
      #expect(calls.filter { $0 == call }.count == 1)
    }
  }

  private func makeFinanceData(
    connection: any ConnectionStateProviding,
    client: any FinanceDataClient
  ) -> FinanceDataStore {
    FinanceDataStore(
      connection: connection,
      client: client,
      calendar: Calendar(identifier: .gregorian),
      now: { Date(timeIntervalSince1970: 1_800_000_000) },
      syncInsights: { _ in }
    )
  }
}

private enum LifecycleFinanceCall: CaseIterable, Hashable {
  case balanceSheet
  case accounts
  case transactions
  case budgets
  case insights
}

private actor LifecycleFinanceDataClient: FinanceDataClient {
  private var session: SureSession
  private var expectedContext: SureRequestContext
  private var calls: [LifecycleFinanceCall] = []

  init(session: SureSession, expectedContext: SureRequestContext) {
    self.session = session
    self.expectedContext = expectedContext
  }

  func fetchBalanceSheet() async throws -> BalanceSheetRecord {
    try await record(.balanceSheet)
    let currency = lifecycleCurrency
    return BalanceSheetRecord(
      currency: currency,
      netWorth: DecimalMoney(amount: 1_000, currency: currency),
      assets: DecimalMoney(amount: 1_250, currency: currency),
      liabilities: DecimalMoney(amount: 250, currency: currency)
    )
  }

  func fetchAccounts() async throws -> [FinanceAccount] {
    try await record(.accounts)
    return [FinanceAccount(
      id: lifecycleID(1),
      name: "Checking",
      institution: "Sure",
      kind: .cash,
      balance: Money(minorUnits: 125_000, currency: lifecycleCurrency),
      tintName: "blue"
    )]
  }

  func fetchTransactions(
    in dateWindow: TransactionDateWindow
  ) async throws -> [FinanceTransaction] {
    try await record(.transactions)
    return [FinanceTransaction(
      id: lifecycleID(2),
      merchant: "Market",
      category: "Groceries",
      symbol: "cart.fill",
      date: try LocalDate(year: 2026, month: 8, day: 28),
      amount: Money(minorUnits: 2_500, currency: lifecycleCurrency),
      kind: .expense,
      accountID: lifecycleID(1)
    )]
  }

  func fetchBudgetCategories() async throws -> [BudgetCategory] {
    try await record(.budgets)
    return [BudgetCategory(
      id: lifecycleID(3),
      name: "Groceries",
      symbol: "cart.fill",
      spent: Money(minorUnits: 2_500, currency: lifecycleCurrency),
      limit: Money(minorUnits: 10_000, currency: lifecycleCurrency)
    )]
  }

  func fetchInsights() async throws -> [BackendInsight] {
    try await record(.insights)
    return [BackendInsight(
      id: "insight-1",
      type: "budget_on_track",
      title: "On track",
      body: "Spending is within the plan.",
      priority: "medium",
      status: "active",
      generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )]
  }

  func recordedCalls() -> [LifecycleFinanceCall] {
    calls
  }

  private func record(_ call: LifecycleFinanceCall) async throws {
    guard try await session.requestContext() == expectedContext else {
      throw LifecycleTestError.unexpectedSession
    }
    calls.append(call)
  }
}

private final class LifecycleCredentialRepository: CredentialRepository, @unchecked Sendable {
  private var snapshot: StoredCredentialSnapshot
  var failNextReplace = false

  init(snapshot: StoredCredentialSnapshot = StoredCredentialSnapshot(session: nil)) {
    self.snapshot = snapshot
  }

  func loadCredentials() throws -> StoredCredentialSnapshot {
    snapshot
  }

  func replaceSession(_ session: StoredAuthenticatedSession?) throws {
    if failNextReplace {
      failNextReplace = false
      throw LifecycleTestError.persistence
    }
    snapshot = StoredCredentialSnapshot(session: session)
  }
}

private final class LifecycleConnectionPreferences: ConnectionPreferences, @unchecked Sendable {
  var hasConnected = false
  func hasConnectedToSure() -> Bool { hasConnected }
  func setHasConnectedToSure(_ connected: Bool) { hasConnected = connected }
  private var savedServerURL: String
  private var explicitlySignedOut = false

  init(serverURL: String) {
    savedServerURL = serverURL
  }

  func serverURL() -> String? { savedServerURL }
  func setServerURL(_ serverURL: String) { savedServerURL = serverURL }
  func isExplicitlySignedOut() -> Bool { explicitlySignedOut }
  func setExplicitlySignedOut(_ isSignedOut: Bool) { explicitlySignedOut = isSignedOut }
}

@MainActor
private struct LifecycleOAuthStub: OAuthAuthenticating {
  func signIn(serverURL: String) async throws -> PasskeyOAuthTokens {
    throw CancellationError()
  }

  func revoke(token: String, serverURL: String) async { }
}

@MainActor
private final class LifecycleNotificationSpy: AuthenticationNotificationLifecycle {
  private(set) var didConnectCount = 0

  func didConnect() async {
    didConnectCount += 1
  }

  func prepareForConnectionChange() async { }
  func prepareForLogout() async { }
}

@MainActor
private final class LifecycleCredentialChangeGate {
  private var didStart = false
  private var continuation: CheckedContinuation<Void, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func begin() async {
    didStart = true
    let waiters = startWaiters
    startWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func end() { }

  func waitUntilStarted() async {
    guard !didStart else { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private enum LifecycleTestError: Error {
  case persistence
  case unexpectedSession
}

private let lifecycleCurrency = CurrencyCode("USD")!

private func lifecycleID(_ value: Int) -> UUID {
  UUID(uuidString: String(
    format: "00000000-0000-4000-8000-%012d",
    value
  ))!
}
