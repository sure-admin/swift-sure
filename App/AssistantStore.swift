import Foundation
import Observation

@MainActor
@Observable
final class AssistantStore {
  var messages: [AssistantMessage]
  var draft = ""
  var isResponding = false
  var errorMessage: String?
  private var chatID: String?
  private let connection: any ConnectionStateProviding
  private let remoteAssistant: any RemoteAssistantClient
  private let localAssistant: any LocalAssistantResponding

  init(
    connection: any ConnectionStateProviding,
    remoteAssistant: any RemoteAssistantClient,
    localAssistant: any LocalAssistantResponding
  ) {
    self.connection = connection
    self.remoteAssistant = remoteAssistant
    self.localAssistant = localAssistant
    messages = [
      AssistantMessage(role: .assistant, content: Self.introduction)
    ]
    updateConnectionPrompts(hasVerifiedAPIKey: connection.hasVerifiedAPIKey)
  }

  func updateConnectionPrompts(hasVerifiedAPIKey: Bool) {
    messages.removeAll { $0.content == Self.appleCardPrompt }
    if hasVerifiedAPIKey {
      messages.insert(
        AssistantMessage(role: .assistant, content: Self.appleCardPrompt),
        at: min(1, messages.endIndex)
      )
    }
  }

  func send(to destination: AssistantDestination) async {
    let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty, !isResponding else { return }
    let sessionGeneration = connection.sessionGeneration
    let conversation = messages
    draft = ""
    messages.append(AssistantMessage(role: .user, content: prompt))
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
      messages.append(AssistantMessage(role: .assistant, content: response))
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

    let identifier: String
    if let chatID {
      identifier = chatID
    } else {
      identifier = try await remoteAssistant.createChat()
      guard connection.isConfigured, connection.sessionGeneration == sessionGeneration else {
        throw CancellationError()
      }
    }
    chatID = identifier
    let response = try await remoteAssistant.sendMessage(prompt, chatID: identifier)
    guard connection.isConfigured, connection.sessionGeneration == sessionGeneration else {
      chatID = nil
      throw CancellationError()
    }
    return response
  }

  private static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError || Task.isCancelled { return true }
    return (error as? URLError)?.code == .cancelled
  }

  private static let introduction = "Here you will be able to ask me anything about your money. I can explain spending, compare accounts, find recurring costs, and help you plan."
  private static let appleCardPrompt = "Want to sync your Apple Card spending with Sure?"
}
