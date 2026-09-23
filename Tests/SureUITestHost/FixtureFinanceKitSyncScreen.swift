import SwiftUI

/// The enrollment remains pending until the UI test releases it. No live services run.
struct FixtureFinanceKitSyncScreen: View {
  @State private var sync: FinanceKitSyncStore
  private let gate: FixtureEnrollmentGate
  @State private var wallet = AppleCardConnectionStore(connector: FixtureSyncWallet())

  init(rejection: FinanceKitBatchRejection? = nil) {
    let gate = FixtureEnrollmentGate()
    self.gate = gate
    _sync = State(initialValue: FinanceKitSyncStore(
      client: FinanceKitControlPlaneClient(transport: SureAPITransport(
        baseURL: URL(string: "https://sure.example")!, dataTransport: FixtureUnusedTransport(),
        authorizer: UnauthenticatedRequestAuthorizer())),
      publisher: FixturePublisher(rejection: rejection), entitlementExpiration: { await gate.wait() }, runSync: { _ in .notConfigured }))
  }

  var body: some View {
    NavigationStack {
      VStack {
        FinanceKitSyncView(sync: sync, wallet: wallet)
        Button("Finish fixture enrollment") { Task { await gate.resume() } }
      }
    }
  }
}

private actor FixtureEnrollmentGate {
  private var continuation: CheckedContinuation<Date?, Never>?
  func wait() async -> Date? { await withCheckedContinuation { continuation = $0 } }
  func resume() { continuation?.resume(returning: nil); continuation = nil }
}

private struct FixturePublisher: FinanceKitPublisherLifecycleHandling {
  var rejection: FinanceKitBatchRejection?
  func requiresRepair() async -> Bool { rejection != nil }
  func batchRejection() async -> FinanceKitBatchRejection? { rejection }
  func batchValidationIssue() async -> FinanceKitEventValidationIssue? {
    rejection == nil ? nil : .init(eventIndex: 7, field: .postedAt, rule: .requiredForBooked)
  }
  func install(configuration: FinanceKitPublisherConfiguration, credential: String) async throws { }
  func blockBackgroundDelivery() { }
  func configuredConnectionID() async -> UUID? {
    rejection == nil ? nil : UUID(uuidString: "20000000-0000-4000-8000-000000000001")
  }
  func renewCredential() async throws { }
  func repair() async throws { }
  func resumeIfConfigured() async { }
  func suspend() async { }
  func disconnect() async throws { }
}

private struct FixtureUnusedTransport: HTTPDataTransport {
  func data(for request: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) }
}

private struct FixtureSyncWallet: AppleCardConnecting {
  var isAvailable: Bool { true }
  func authorizationStatus() async throws -> AppleCardAuthorization { .authorized }
  func requestAuthorization() async throws -> AppleCardAuthorization { .authorized }
  func fetchAccounts() async throws -> [LocalFinancialAccount] {
    [.init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
      name: "Wallet fixture", institutionName: "Wallet", kind: .liability,
      balance: Money(minorUnits: 100, currency: CurrencyCode("USD")!))]
  }
}
