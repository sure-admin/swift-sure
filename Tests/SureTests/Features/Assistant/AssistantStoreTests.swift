import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Assistant store")
struct AssistantStoreTests {
  @Test("Local messages use the injected on-device responder")
  func localResponse() async {
    let remoteAssistant = RemoteAssistantSpy()
    let store = makeStore(
      connection: AssistantConnectionStub(isConfigured: true),
      remoteAssistant: remoteAssistant,
      localResponse: "A private on-device answer."
    )
    store.draft = "How am I doing?"

    await store.send(to: .localModel)

    let remoteSnapshot = await remoteAssistant.snapshot()
    #expect(store.messages.suffix(2).map(\.content) == [
      "How am I doing?",
      "A private on-device answer."
    ])
    #expect(store.errorMessage == nil)
    #expect(remoteSnapshot.createChatCount == 0)
  }

  @Test("Remote messages reuse the injected chat")
  func remoteChatReuse() async {
    let remoteAssistant = RemoteAssistantSpy()
    let store = makeStore(
      connection: AssistantConnectionStub(isConfigured: true),
      remoteAssistant: remoteAssistant
    )

    store.draft = "First question"
    await store.send(to: .sureServer)
    store.draft = "Second question"
    await store.send(to: .sureServer)

    let snapshot = await remoteAssistant.snapshot()
    #expect(snapshot.createChatCount == 1)
    #expect(snapshot.messages == ["First question", "Second question"])
    #expect(snapshot.chatIDs == [deterministicUUID(1), deterministicUUID(1)])
    #expect(store.messages.last?.content == "Sure answered: Second question")
  }

  @Test("Loads and switches between saved conversations")
  func savedConversationSelection() async {
    let conversation = AssistantConversation(
      id: deterministicUUID(7),
      title: "Review unusually high restaurant spending this month",
      updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    let detail = AssistantConversationDetail(
      conversation: conversation,
      messages: [
        AssistantMessage(
          id: deterministicUUID(8),
          role: .user,
          content: "Why is dining higher?",
          date: Date(timeIntervalSince1970: 1_700_000_090)
        ),
        AssistantMessage(
          id: deterministicUUID(9),
          role: .assistant,
          content: "Three extra restaurant visits drove the increase.",
          date: Date(timeIntervalSince1970: 1_700_000_100)
        )
      ]
    )
    let remote = RemoteAssistantSpy(conversations: [conversation], details: [conversation.id: detail])
    let store = makeStore(
      connection: AssistantConnectionStub(isConfigured: true),
      remoteAssistant: remote
    )

    await store.refreshConversations()
    await store.selectConversation(conversation)

    #expect(store.conversations == [conversation])
    #expect(store.selectedConversationID == conversation.id)
    #expect(store.messages.map(\.content) == [
      "Why is dining higher?",
      "Three extra restaurant visits drove the increase."
    ])
  }

  @Test("New remote chats use an abbreviated prompt title")
  func remoteChatTitle() async throws {
    let remote = RemoteAssistantSpy()
    let store = makeStore(
      connection: AssistantConnectionStub(isConfigured: true),
      remoteAssistant: remote
    )
    store.draft = String(repeating: "Long financial question ", count: 8)

    await store.send(to: .sureServer)

    let snapshot = await remote.snapshot()
    let title = try #require(snapshot.titles.first)
    #expect(title.count == 80)
    #expect(title.hasSuffix("…"))
  }

  @Test("Messages use injected identifiers and dates")
  func deterministicMessageMetadata() async {
    let values = AssistantMessageValues()
    let store = AssistantStore(
      connection: AssistantConnectionStub(isConfigured: true),
      remoteAssistant: RemoteAssistantSpy(),
      localAssistant: LocalAssistantStub(response: "Local answer"),
      makeID: values.makeID,
      now: values.now
    )
    store.draft = "A local question"

    await store.send(to: .localModel)

    #expect(store.messages.map(\.id) == [
      deterministicUUID(1),
      deterministicUUID(2),
      deterministicUUID(3)
    ])
    #expect(store.messages.map(\.date) == [
      Date(timeIntervalSince1970: 1_700_000_000),
      Date(timeIntervalSince1970: 1_700_000_001),
      Date(timeIntervalSince1970: 1_700_000_002)
    ])
  }

  @Test("Remote messages require a configured connection")
  func remoteRequiresConnection() async {
    let remoteAssistant = RemoteAssistantSpy()
    let store = makeStore(
      connection: AssistantConnectionStub(isConfigured: false),
      remoteAssistant: remoteAssistant
    )
    store.draft = "Send this"

    await store.send(to: .sureServer)

    let remoteSnapshot = await remoteAssistant.snapshot()
    #expect(store.errorMessage == SureAPIError.unauthorized.localizedDescription)
    #expect(remoteSnapshot.createChatCount == 0)
  }

  @Test("A response failure resets the sending state")
  func responseFailure() async {
    let values = AssistantMessageValues()
    let store = AssistantStore(
      connection: AssistantConnectionStub(isConfigured: true),
      remoteAssistant: RemoteAssistantSpy(),
      localAssistant: FailingLocalAssistantStub(),
      makeID: values.makeID,
      now: values.now
    )
    store.draft = "Fail this response"

    await store.send(to: .localModel)

    #expect(store.isResponding == false)
    #expect(store.errorMessage == AssistantTestFailure.expected.localizedDescription)
  }

  @Test("A session change discards an in-flight reply and its remote chat")
  func sessionChangeInvalidatesReply() async {
    let connection = AssistantConnectionStub(isConfigured: true)
    let remote = SessionSwitchRemoteAssistant()
    let values = AssistantMessageValues()
    let store = AssistantStore(
      connection: connection,
      remoteAssistant: remote,
      localAssistant: LocalAssistantStub(response: "Local answer"),
      makeID: values.makeID,
      now: values.now
    )
    store.draft = "Old account question"
    let firstSend = Task { await store.send(to: .sureServer) }
    await remote.waitUntilFirstMessageStarted()

    connection.sessionGeneration += 1
    await remote.completeFirstMessage()
    await firstSend.value

    #expect(!store.messages.map(\.content).contains("Old account answer"))
    #expect(store.errorMessage == nil)

    store.draft = "New account question"
    await store.send(to: .sureServer)
    #expect(await remote.createCount == 2)
    #expect(store.messages.last?.content == "New account answer")
  }

  @Test("A session change during chat creation discards the old chat before sending")
  func sessionChangeInvalidatesChatCreation() async {
    let connection = AssistantConnectionStub(isConfigured: true)
    let remote = SuspendedChatCreationRemoteAssistant()
    let values = AssistantMessageValues()
    let store = AssistantStore(
      connection: connection,
      remoteAssistant: remote,
      localAssistant: LocalAssistantStub(response: "Local answer"),
      makeID: values.makeID,
      now: values.now
    )
    store.draft = "Old account question"
    let firstSend = Task { await store.send(to: .sureServer) }
    await remote.waitUntilFirstCreationStarted()

    connection.sessionGeneration += 1
    await remote.completeFirstCreation()
    await firstSend.value

    var snapshot = await remote.snapshot()
    #expect(snapshot.createChatCount == 1)
    #expect(snapshot.messages.isEmpty)
    #expect(snapshot.chatIDs.isEmpty)
    #expect(store.errorMessage == nil)

    store.draft = "New account question"
    await store.send(to: .sureServer)

    snapshot = await remote.snapshot()
    #expect(snapshot.createChatCount == 2)
    #expect(snapshot.messages == ["New account question"])
    #expect(snapshot.chatIDs == [deterministicUUID(2)])
    #expect(store.messages.last?.content == "Sure answered: New account question")
  }

  private func makeStore(
    connection: AssistantConnectionStub,
    remoteAssistant: RemoteAssistantSpy = RemoteAssistantSpy(),
    localResponse: String = "Local answer"
  ) -> AssistantStore {
    let values = AssistantMessageValues()
    return AssistantStore(
      connection: connection,
      remoteAssistant: remoteAssistant,
      localAssistant: LocalAssistantStub(response: localResponse),
      makeID: values.makeID,
      now: values.now
    )
  }
}

private final class AssistantConnectionStub: ConnectionStateProviding {
  var isConfigured: Bool
  var sessionGeneration = 0

  init(isConfigured: Bool) {
    self.isConfigured = isConfigured
  }
}

@MainActor
private struct LocalAssistantStub: LocalAssistantResponding {
  var response: String

  func respond(to prompt: String, conversation: [AssistantMessage]) async throws -> String {
    response
  }
}

@MainActor
private struct FailingLocalAssistantStub: LocalAssistantResponding {
  func respond(to prompt: String, conversation: [AssistantMessage]) async throws -> String {
    throw AssistantTestFailure.expected
  }
}

private actor RemoteAssistantSpy: RemoteAssistantClient {
  private var createChatCount = 0
  private var messages: [String] = []
  private var chatIDs: [UUID] = []
  private var titles: [String] = []
  private var conversations: [AssistantConversation]
  private var details: [UUID: AssistantConversationDetail]

  init(
    conversations: [AssistantConversation] = [],
    details: [UUID: AssistantConversationDetail] = [:]
  ) {
    self.conversations = conversations
    self.details = details
  }

  func fetchConversations() async throws -> [AssistantConversation] {
    conversations
  }

  func fetchConversation(id: UUID) async throws -> AssistantConversationDetail {
    guard let detail = details[id] else { throw AssistantTestFailure.expected }
    return detail
  }

  func createChat(title: String) async throws -> UUID {
    createChatCount += 1
    titles.append(title)
    return deterministicUUID(createChatCount)
  }

  func sendMessage(_ content: String, chatID: UUID) async throws -> String {
    messages.append(content)
    chatIDs.append(chatID)
    return "Sure answered: \(content)"
  }

  func snapshot() -> RemoteAssistantSnapshot {
    RemoteAssistantSnapshot(
      createChatCount: createChatCount,
      messages: messages,
      chatIDs: chatIDs,
      titles: titles
    )
  }
}

private actor SessionSwitchRemoteAssistant: RemoteAssistantClient {
  private(set) var createCount = 0
  private var messageCount = 0
  private var firstMessageContinuation: CheckedContinuation<Void, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var firstMessageStarted = false

  func fetchConversations() async throws -> [AssistantConversation] { [] }

  func fetchConversation(id: UUID) async throws -> AssistantConversationDetail {
    throw AssistantTestFailure.expected
  }

  func createChat(title: String) async throws -> UUID {
    createCount += 1
    return deterministicUUID(createCount)
  }

  func sendMessage(_ content: String, chatID: UUID) async throws -> String {
    messageCount += 1
    if messageCount == 1 {
      await withCheckedContinuation { continuation in
        firstMessageContinuation = continuation
        firstMessageStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
      }
      return "Old account answer"
    }
    return "New account answer"
  }

  func waitUntilFirstMessageStarted() async {
    guard !firstMessageStarted else { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func completeFirstMessage() {
    firstMessageContinuation?.resume()
    firstMessageContinuation = nil
  }
}

private actor SuspendedChatCreationRemoteAssistant: RemoteAssistantClient {
  private var createCount = 0
  private var messages: [String] = []
  private var chatIDs: [UUID] = []
  private var firstCreationContinuation: CheckedContinuation<Void, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var firstCreationStarted = false

  func fetchConversations() async throws -> [AssistantConversation] { [] }

  func fetchConversation(id: UUID) async throws -> AssistantConversationDetail {
    throw AssistantTestFailure.expected
  }

  func createChat(title: String) async throws -> UUID {
    createCount += 1
    let identifier = deterministicUUID(createCount)
    if createCount == 1 {
      await withCheckedContinuation { continuation in
        firstCreationContinuation = continuation
        firstCreationStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
      }
    }
    return identifier
  }

  func sendMessage(_ content: String, chatID: UUID) async throws -> String {
    messages.append(content)
    chatIDs.append(chatID)
    return "Sure answered: \(content)"
  }

  func waitUntilFirstCreationStarted() async {
    guard !firstCreationStarted else { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func completeFirstCreation() {
    firstCreationContinuation?.resume()
    firstCreationContinuation = nil
  }

  func snapshot() -> RemoteAssistantSnapshot {
    RemoteAssistantSnapshot(
      createChatCount: createCount,
      messages: messages,
      chatIDs: chatIDs,
      titles: []
    )
  }
}

private struct RemoteAssistantSnapshot {
  var createChatCount: Int
  var messages: [String]
  var chatIDs: [UUID]
  var titles: [String]
}

private final class AssistantMessageValues {
  private var identifierSequence = 1
  private var dateSequence: TimeInterval = 0

  func makeID() -> UUID {
    defer { identifierSequence += 1 }
    return deterministicUUID(identifierSequence)
  }

  func now() -> Date {
    defer { dateSequence += 1 }
    return Date(timeIntervalSince1970: 1_700_000_000 + dateSequence)
  }
}

private func deterministicUUID(_ sequence: Int) -> UUID {
  UUID(uuid: (
    0, 0, 0, 0,
    0, 0,
    0, 0,
    0, 0,
    0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: sequence)
  ))
}

private enum AssistantTestFailure: LocalizedError {
  case expected

  var errorDescription: String? { "Expected assistant failure" }
}
