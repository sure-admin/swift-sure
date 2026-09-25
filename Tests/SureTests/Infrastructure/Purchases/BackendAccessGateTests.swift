import Foundation
import Testing
@testable import Sure

struct BackendAccessGateTests {
  @Test func cancellationBeforeTaskInstallationIsNotLost() async throws {
    let gate = entitledTestGate()
    let cancellation = SubscriptionRequestCancellation()
    let permit = try gate.permit()
    let id = UUID()
    try gate.register(id, permit: permit, cancel: { cancellation.cancel() })
    defer { gate.unregister(id) }
    gate.update(expiration: nil)
    let task = Task { }
    cancellation.install { task.cancel() }
    #expect(task.isCancelled)
    #expect(throws: BackendAccessError.self) { try gate.validate(permit) }
    await task.value
  }

  @Test func lockedTransportNeverContactsBackend() async throws {
    let base = HTTPDataTransportStub([])
    let gate = BackendAccessGate()
    let transport = SubscriptionHTTPDataTransport(base: base, gate: gate)
    for method in ["GET", "POST", "PATCH", "DELETE"] {
      var request = URLRequest(url: URL(string: "https://sure.example/api/v1/accounts")!)
      request.httpMethod = method
      await #expect(throws: BackendAccessError.self) { try await transport.data(for: request) }
    }
    #expect(await base.requests().isEmpty)
  }

  @Test func verifiedAccessAllowsRequests() async throws {
    let now = Date(timeIntervalSince1970: 100)
    let gate = BackendAccessGate(now: { now })
    gate.update(expiration: now.addingTimeInterval(60))
    let base = HTTPDataTransportStub([try .http(json: "{}")])
    let transport = SubscriptionHTTPDataTransport(base: base, gate: gate)
    _ = try await transport.data(for: URLRequest(url: URL(string: "https://sure.example")!))
    #expect(await base.requests().count == 1)
  }

  @Test func publicDemoWorksWithoutSubscriptionButOtherHostsRemainLocked() async throws {
    let gate = BackendAccessGate()
    let demo = SureDemoServer.baseURL.appending(path: "api/v1/accounts")
    let base = HTTPDataTransportStub([try .http(json: "{}", url: demo)])
    let transport = SubscriptionHTTPDataTransport(base: base, gate: gate)

    _ = try await transport.data(for: URLRequest(url: demo))
    #expect(await base.requests().count == 1)
    #expect(gate.isAllowed(for: SureDemoServer.baseURL))
    #expect(!gate.isAllowed)

    for url in [
      "https://demo.sure.am.evil.example/api/v1/accounts",
      "http://demo.sure.am/api/v1/accounts",
      "https://demo.sure.am:8443/api/v1/accounts",
      "https://sure.example/api/v1/accounts"
    ] {
      await #expect(throws: BackendAccessError.self) {
        try await transport.data(for: URLRequest(url: URL(string: url)!))
      }
    }
    #expect(await base.requests().count == 1)
  }

  @Test func subscriptionExpiryDoesNotCancelPublicDemoRequests() async throws {
    let gate = BackendAccessGate()
    gate.update(expiration: .distantFuture)
    let permit = try gate.permit(for: SureDemoServer.baseURL)
    let cancellation = SubscriptionRequestCancellation()
    let id = UUID()
    try gate.register(id, permit: permit, for: SureDemoServer.baseURL, cancel: { cancellation.cancel() })
    defer { gate.unregister(id) }
    gate.update(expiration: nil)
    try gate.validate(permit, for: SureDemoServer.baseURL)
    #expect(throws: BackendAccessError.self) {
      try gate.validate(permit, for: URL(string: "https://sure.example"))
    }
    let task = Task { }
    cancellation.install { task.cancel() }
    #expect(!task.isCancelled)
    await task.value
  }

  @Test func publicDemoRedirectsCannotLeaveTheCanonicalHost() {
    let demo = SureDemoServer.baseURL.appending(path: "api/v1/accounts")
    #expect(DemoRedirectPolicy.allowsRedirect(from: demo,
      to: URL(string: "https://demo.sure.am/api/v1/accounts?page=2")))
    #expect(!DemoRedirectPolicy.allowsRedirect(from: demo,
      to: URL(string: "https://other.example/api/v1/accounts")))
    #expect(!DemoRedirectPolicy.allowsRedirect(from: demo,
      to: URL(string: "http://demo.sure.am/api/v1/accounts")))
  }

  @Test func publicDemoDiscardsResponsesFromAnotherHost() async throws {
    let gate = BackendAccessGate()
    let base = HTTPDataTransportStub([try .http(json: "{}", url: URL(string: "https://other.example")!)])
    let transport = SubscriptionHTTPDataTransport(base: base, gate: gate)
    await #expect(throws: BackendAccessError.self) {
      try await transport.data(for: URLRequest(url: SureDemoServer.baseURL))
    }
  }

  @Test func revocationDiscardsAnInFlightResponseEvenAfterRestoration() async throws {
    let gate = entitledTestGate()
    let base = SuspendedPurchaseTransport()
    let transport = SubscriptionHTTPDataTransport(base: base, gate: gate)
    let request = URLRequest(url: URL(string: "https://sure.example")!)
    let task = Task { try await transport.data(for: request) }
    await base.waitUntilStarted()
    gate.update(expiration: nil)
    gate.update(expiration: .distantFuture)
    await base.complete()
    do {
      _ = try await task.value
      Issue.record("A revoked in-flight response must never be delivered")
    } catch { }
  }

  @Test func expirationAndRevocationInvalidatePermits() throws {
    let now = Date(timeIntervalSince1970: 100)
    let gate = BackendAccessGate(now: { now })
    gate.update(expiration: now.addingTimeInterval(60))
    let permit = try gate.permit()
    gate.update(expiration: nil)
    gate.update(expiration: now.addingTimeInterval(120))
    #expect(throws: BackendAccessError.self) { try gate.validate(permit) }
    gate.update(expiration: now)
    #expect(!gate.isAllowed)
  }
}

func entitledTestGate() -> BackendAccessGate {
  let gate = BackendAccessGate()
  gate.update(expiration: .distantFuture)
  return gate
}

private actor SuspendedPurchaseTransport: HTTPDataTransport {
  private var continuation: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      started?.resume()
      started = nil
    }
    return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }
  func waitUntilStarted() async {
    if continuation != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func complete() { continuation?.resume(); continuation = nil }
}
