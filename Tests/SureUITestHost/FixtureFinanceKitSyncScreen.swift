import SwiftUI

/// The enrollment remains pending until the UI test releases it. No live services run.
struct FixtureFinanceKitSyncScreen: View {
  @State private var sync: FinanceKitSyncStore
  private let gate: FixtureEnrollmentGate
  private let accounts = [LocalFinancialAccount(
    id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "Wallet fixture",
    institutionName: "Wallet", kind: .liability,
    balance: Money(minorUnits: 100, currency: CurrencyCode("USD")!))]

  init() {
    let gate = FixtureEnrollmentGate()
    self.gate = gate
    _sync = State(initialValue: FinanceKitSyncStore(
      client: FinanceKitControlPlaneClient(transport: SureAPITransport(
        baseURL: URL(string: "https://sure.example")!, dataTransport: FixtureUnusedTransport(),
        authorizer: UnauthenticatedRequestAuthorizer())),
      publisher: FixturePublisher(), entitlementExpiration: { await gate.wait() }, runSync: { _ in .notConfigured }))
  }

  var body: some View {
    NavigationStack {
      VStack {
        FinanceKitSyncView(sync: sync, accounts: accounts)
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
  func install(configuration: FinanceKitPublisherConfiguration, credential: String) async throws { }
  func blockBackgroundDelivery() { }
  func configuredConnectionID() async -> UUID? { nil }
  func resumeIfConfigured() async { }
  func suspend() async { }
  func disconnect() async throws { }
}

private struct FixtureUnusedTransport: HTTPDataTransport {
  func data(for request: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) }
}
