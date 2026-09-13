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
