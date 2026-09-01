import Foundation
import Observation

@MainActor
@Observable
final class AssistantStore {
  var messages: [AssistantMessage]
  var conversations: [AssistantConversation] = []
  var draft = ""
  var isResponding = false
  var isLoadingConversations = false
  var isLoadingConversation = false
  var errorMessage: String?
  var conversationErrorMessage: String?
  private var chatID: UUID?
  private(set) var selectedConversationID: UUID?
  private var conversationLoadGeneration = 0
  private var selectionGeneration = 0
  private let connection: any ConnectionStateProviding
  private let remoteAssistant: any RemoteAssistantClient
  private let localAssistant: any LocalAssistantResponding
  private let makeID: () -> UUID
  private let now: () -> Date

  init(
    connection: any ConnectionStateProviding,
    remoteAssistant: any RemoteAssistantClient,
    localAssistant: any LocalAssistantResponding,
    makeID: @escaping () -> UUID,
    now: @escaping () -> Date
  ) {
    self.connection = connection
    self.remoteAssistant = remoteAssistant
    self.localAssistant = localAssistant
    self.makeID = makeID
    self.now = now
    messages = [
      AssistantMessage(
        id: makeID(),
        role: .assistant,
        content: Self.introduction,
        date: now()
      )
    ]
  }

  func reloadConversationsForCurrentSession() async {
    conversationLoadGeneration += 1
    selectionGeneration += 1
    chatID = nil
    selectedConversationID = nil
    conversations = []
    draft = ""
    errorMessage = nil
    conversationErrorMessage = nil
    isLoadingConversations = false
    isLoadingConversation = false
    resetMessages()
    await refreshConversations()
  }

  func refreshConversations() async {
    conversationLoadGeneration += 1
    let requestGeneration = conversationLoadGeneration
    let sessionGeneration = connection.sessionGeneration
    guard connection.isConfigured else {
      conversations = []
      conversationErrorMessage = nil
      isLoadingConversations = false
      return
    }

    isLoadingConversations = true
    conversationErrorMessage = nil
    do {
      let fetched = try await remoteAssistant.fetchConversations()
      guard requestGeneration == conversationLoadGeneration,
            sessionGeneration == connection.sessionGeneration else { return }
      conversations = fetched
    } catch {
      guard requestGeneration == conversationLoadGeneration,
            sessionGeneration == connection.sessionGeneration else { return }
      conversationErrorMessage = error.localizedDescription
    }
    if requestGeneration == conversationLoadGeneration {
      isLoadingConversations = false
    }
  }

  func selectConversation(_ conversation: AssistantConversation) async {
    guard connection.isConfigured, !isResponding else { return }
    selectionGeneration += 1
    let requestGeneration = selectionGeneration
    let sessionGeneration = connection.sessionGeneration
    isLoadingConversation = true
    conversationErrorMessage = nil
    errorMessage = nil

    do {
      let detail = try await remoteAssistant.fetchConversation(id: conversation.id)
      guard requestGeneration == selectionGeneration,
            sessionGeneration == connection.sessionGeneration else { return }
      chatID = detail.conversation.id
      selectedConversationID = detail.conversation.id
      draft = ""
      if detail.messages.isEmpty {
        resetMessages()
      } else {
        messages = detail.messages
      }
      replaceConversation(detail.conversation)
    } catch {
      guard requestGeneration == selectionGeneration,
            sessionGeneration == connection.sessionGeneration else { return }
      conversationErrorMessage = error.localizedDescription
    }
    if requestGeneration == selectionGeneration {
      isLoadingConversation = false
    }
  }

  func startNewConversation() {
    guard !isResponding else { return }
    selectionGeneration += 1
    chatID = nil
    selectedConversationID = nil
    draft = ""
    errorMessage = nil
    conversationErrorMessage = nil
    isLoadingConversation = false
    resetMessages()
  }

  func send(to destination: AssistantDestination) async {
    let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty, !isResponding else { return }
    let sessionGeneration = connection.sessionGeneration
    let conversation = messages
    draft = ""
    messages.append(makeMessage(role: .user, content: prompt))
    isResponding = true
    errorMessage = nil

    do {
      let response: String
      switch destination {
      case .localModel:
        response = try await localAssistant.respond(to: prompt, conversation: conversation)
      case .sureServer:
        response = try await sendToSure(prompt, sessionGeneration: sessionGeneration)
      }
      guard connection.sessionGeneration == sessionGeneration else { throw CancellationError() }
      messages.append(makeMessage(role: .assistant, content: response))
    } catch {
      if !Self.isCancellation(error), connection.sessionGeneration == sessionGeneration {
        errorMessage = error.localizedDescription
      }
    }
    isResponding = false
  }

  private func sendToSure(_ prompt: String, sessionGeneration: Int) async throws -> String {
    guard connection.isConfigured, connection.sessionGeneration == sessionGeneration else {
      throw SureAPIError.unauthorized
    }

    let identifier: UUID
    if let chatID {
      identifier = chatID
    } else {
      let title = conversationTitle(for: prompt)
      identifier = try await remoteAssistant.createChat(title: title)
      guard connection.isConfigured, connection.sessionGeneration == sessionGeneration else {
        throw CancellationError()
      }
      selectedConversationID = identifier
      replaceConversation(
        AssistantConversation(id: identifier, title: title, updatedAt: now())
      )
    }
    chatID = identifier
    let response = try await remoteAssistant.sendMessage(prompt, chatID: identifier)
    guard connection.isConfigured, connection.sessionGeneration == sessionGeneration else {
      chatID = nil
      throw CancellationError()
    }
    if let index = conversations.firstIndex(where: { $0.id == identifier }) {
      var conversation = conversations.remove(at: index)
      conversation.updatedAt = now()
      conversations.insert(conversation, at: 0)
    }
    return response
  }

  private func resetMessages() {
    messages = initialMessages()
  }

  private func initialMessages() -> [AssistantMessage] {
    [makeMessage(role: .assistant, content: Self.introduction)]
  }

  private func replaceConversation(_ conversation: AssistantConversation) {
    conversations.removeAll { $0.id == conversation.id }
    conversations.insert(conversation, at: 0)
  }

  private func conversationTitle(for prompt: String) -> String {
    AssistantConversation.abridgedTitle(prompt, limit: 80)
  }

  private func makeMessage(role: AssistantRole, content: String) -> AssistantMessage {
    AssistantMessage(id: makeID(), role: role, content: content, date: now())
  }

  private static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError || Task.isCancelled { return true }
    return (error as? URLError)?.code == .cancelled
  }

  private static let introduction = "Here you will be able to ask me anything about your money. I can explain spending, compare accounts, find recurring costs, and help you plan."
}
