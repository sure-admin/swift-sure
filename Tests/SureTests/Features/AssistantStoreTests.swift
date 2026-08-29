import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Assistant store")
struct AssistantStoreTests {
  @Test("Verified API keys add the Apple Card prompt")
  func verifiedAPIKeyPrompt() {
    let store = makeStore(
      connection: AssistantConnectionStub(
        isConfigured: true,
        hasVerifiedAPIKey: true
      )
    )

    #expect(store.messages.map(\.content).contains("Want to sync your Apple Card spending with Sure?"))
  }

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
    #expect(snapshot.chatIDs == ["chat-1", "chat-1"])
    #expect(store.messages.last?.content == "Sure answered: Second question")
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
    let store = AssistantStore(
      connection: AssistantConnectionStub(isConfigured: true),
      remoteAssistant: RemoteAssistantSpy(),
      localAssistant: FailingLocalAssistantStub()
    )
    store.draft = "Fail this response"

    await store.send(to: .localModel)

    #expect(store.isResponding == false)
    #expect(store.errorMessage == AssistantTestFailure.expected.localizedDescription)
  }

  private func makeStore(
    connection: AssistantConnectionStub,
    remoteAssistant: RemoteAssistantSpy = RemoteAssistantSpy(),
    localResponse: String = "Local answer"
  ) -> AssistantStore {
    AssistantStore(
      connection: connection,
      remoteAssistant: remoteAssistant,
      localAssistant: LocalAssistantStub(response: localResponse)
    )
  }
}

private final class AssistantConnectionStub: ConnectionStateProviding {
  var isConfigured: Bool
  var hasVerifiedAPIKey: Bool

  init(isConfigured: Bool, hasVerifiedAPIKey: Bool = false) {
    self.isConfigured = isConfigured
    self.hasVerifiedAPIKey = hasVerifiedAPIKey
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
  private var chatIDs: [String] = []

  func createChat() async throws -> String {
    createChatCount += 1
    return "chat-\(createChatCount)"
  }

  func sendMessage(_ content: String, chatID: String) async throws -> String {
    messages.append(content)
    chatIDs.append(chatID)
    return "Sure answered: \(content)"
  }

  func snapshot() -> RemoteAssistantSnapshot {
    RemoteAssistantSnapshot(
      createChatCount: createChatCount,
      messages: messages,
      chatIDs: chatIDs
    )
  }
}

private struct RemoteAssistantSnapshot {
  var createChatCount: Int
  var messages: [String]
  var chatIDs: [String]
}

private enum AssistantTestFailure: LocalizedError {
  case expected

  var errorDescription: String? { "Expected assistant failure" }
}
