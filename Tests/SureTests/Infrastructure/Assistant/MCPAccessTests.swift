import Foundation
import Observation
import Testing
@testable import Sure

@MainActor
@Suite("MCP access preference and approval")
struct MCPAccessTests {
  @Test func preferenceDefaultsOffAndPersistsLocally() throws {
    let suite = "MCPAccessTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = UserDefaultsMCPAccessPreferences(defaults: defaults)
    #expect(!preferences.allowsAutomaticAccess())
    preferences.setAllowsAutomaticAccess(true)
    #expect(UserDefaultsMCPAccessPreferences(defaults: defaults).allowsAutomaticAccess())
    preferences.setAllowsAutomaticAccess(false)
    #expect(!preferences.allowsAutomaticAccess())
  }

  @Test func approvalResumesExactCallWithoutEnablingPreference() async throws {
    let preferences = MemoryMCPPreferences()
    let access = makeAccess(preferences)
    let stub = try callResponses()
    let service = try await makeService(stub, access: access)
    let task = Task { try await service.call(name: "get_accounts", argumentsJSON: #"{"include_balance_series":true}"#) }
    await waitForRequest(access)
    let request = try #require(access.pendingRequest)
    #expect(request.operation == "get_accounts")
    #expect(request.arguments.contains("include_balance_series"))
    #expect(request.server.absoluteString == "https://sure.example")
    #expect(await stub.requests().isEmpty)
    access.resolve(id: request.id, decision: .allowOnce)
    #expect(try await task.value.contains("Sure server via MCP"))
    #expect(await stub.requests().count == 4)
    #expect(!preferences.allowed)
    #expect(access.pendingRequest == nil)
  }

  @Test func discoveryAlsoWaitsForPermission() async throws {
    let access = makeAccess()
    let stub = HTTPDataTransportStub([])
    let service = try await makeService(stub, access: access)
    let task = Task { try await service.discover() }
    await waitForRequest(access)
    #expect(access.pendingRequest?.operation == "Read available Sure tools")
    #expect(await stub.requests().isEmpty)
    access.cancelPending()
    await #expect(throws: MCPAccessStore.AccessError.self) { try await task.value }
    #expect(await stub.requests().isEmpty)
  }

  @Test func alwaysAllowPersistsAndTurningOffPromptsAgain() async throws {
    let preferences = MemoryMCPPreferences()
    let access = makeAccess(preferences)
    let first = Task { try await access.authorize(server: server, operation: "get_accounts", arguments: "{}") }
    await waitForRequest(access)
    access.resolve(id: try #require(access.pendingRequest).id, decision: .alwaysAllow)
    try await first.value
    #expect(preferences.allowed)
    try await access.authorize(server: server, operation: "get_budget", arguments: "{}")
    #expect(access.pendingRequest == nil)
    access.allowsAutomaticAccess = false
    let next = Task { try await access.authorize(server: server, operation: "get_budget", arguments: "{}") }
    await waitForRequest(access)
    access.cancelPending()
    await #expect(throws: MCPAccessStore.AccessError.self) { try await next.value }
    #expect(!preferences.allowed)
  }

  @Test func cancellationClearsSuspendedApproval() async throws {
    let access = makeAccess()
    let task = Task { try await access.authorize(server: server, operation: "get_accounts", arguments: "{}") }
    await waitForRequest(access)
    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
    #expect(access.pendingRequest == nil)
  }

  @Test func leavingAssistantCancelsAndBlocksFurtherRequests() async throws {
    let access = makeAccess()
    let task = Task { try await access.authorize(server: server, operation: "get_accounts", arguments: "{}") }
    await waitForRequest(access)
    access.setPresentationAvailable(false)
    await #expect(throws: MCPAccessStore.AccessError.self) { try await task.value }
    await #expect(throws: CancellationError.self) {
      try await access.authorize(server: server, operation: "get_accounts", arguments: "{}")
    }
  }

  @Test func connectionChangeWhileDialogIsOpenCannotRedirectApprovedCall() async throws {
    let access = makeAccess()
    let stub = HTTPDataTransportStub([])
    let session = SureSession(context: try SureRequestContext(baseURL: server, authorization: .bearer("first")))
    let client = try await SureMCPClient(session: session, dataTransport: stub, makeID: { requestID }).boundToCurrentSession()
    let service = ConsentedMCPService(client: client, server: server, access: access)
    let task = Task { try await service.call(name: "get_accounts", argumentsJSON: "{}") }
    await waitForRequest(access)
    await session.replaceContext(with: try SureRequestContext(baseURL: URL(string: "https://other.example")!, authorization: .bearer("second")))
    access.resolve(id: try #require(access.pendingRequest).id, decision: .allowOnce)
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await stub.requests().isEmpty)
  }

  @Test func invalidOrWriteCallsNeverPrompt() async throws {
    let access = makeAccess()
    let stub = HTTPDataTransportStub([])
    let service = try await makeService(stub, access: access)
    await #expect(throws: SureToolDelegationError.unavailable) { try await service.call(name: "update_budget", argumentsJSON: "{}") }
    await #expect(throws: SureToolDelegationError.invalidArguments) { try await service.call(name: "get_accounts", argumentsJSON: "[]") }
    #expect(access.pendingRequest == nil)
    #expect(await stub.requests().isEmpty)
  }

  @Test func automaticAccessExecutesWithoutDialog() async throws {
    let preferences = MemoryMCPPreferences()
    preferences.allowed = true
    let access = makeAccess(preferences)
    let stub = try callResponses()
    let service = try await makeService(stub, access: access)
    _ = try await service.call(name: "get_accounts", argumentsJSON: "{}")
    #expect(access.pendingRequest == nil)
    #expect(await stub.requests().count == 4)
  }

  @Test func concurrentRequestCannotReplaceVisibleApproval() async throws {
    let access = makeAccess()
    let first = Task { try await access.authorize(server: server, operation: "first", arguments: "{}") }
    await waitForRequest(access)
    let id = try #require(access.pendingRequest).id
    await #expect(throws: MCPAccessStore.AccessError.self) {
      try await access.authorize(server: server, operation: "second", arguments: "{}")
    }
    #expect(access.pendingRequest?.id == id)
    access.resolve(id: id, decision: .allowOnce)
    try await first.value
  }

  private func makeAccess(_ preferences: MemoryMCPPreferences? = nil) -> MCPAccessStore {
    let access = MCPAccessStore(preferences: preferences ?? MemoryMCPPreferences(), makeID: { UUID() })
    access.setPresentationAvailable(true)
    return access
  }

  private func makeService(_ stub: HTTPDataTransportStub, access: MCPAccessStore) async throws -> ConsentedMCPService {
    let context = try SureRequestContext(baseURL: server, authorization: .bearer("synthetic"))
    let client = try await SureMCPClient(session: SureSession(context: context), dataTransport: stub, makeID: { requestID }).boundToCurrentSession()
    return ConsentedMCPService(client: client, server: server, access: access)
  }

  private func callResponses() throws -> HTTPDataTransportStub {
    HTTPDataTransportStub([try .http(fixture: "mcp-initialize"), try .http(status: 204), try .http(fixture: "mcp-tools"), try .http(fixture: "mcp-success")])
  }

  private func waitForRequest(_ access: MCPAccessStore) async {
    guard access.pendingRequest == nil else { return }
    await withCheckedContinuation { continuation in
      withObservationTracking {
        _ = access.pendingRequest
      } onChange: {
        Task { @MainActor in continuation.resume() }
      }
    }
  }
}

@MainActor
private final class MemoryMCPPreferences: MCPAccessPreferences {
  var allowed = false
  func allowsAutomaticAccess() -> Bool { allowed }
  func setAllowsAutomaticAccess(_ allowed: Bool) { self.allowed = allowed }
}
private let server = URL(string: "https://sure.example")!
private let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
