import Foundation
import Testing
@testable import Sure

@Suite("Chats and push API clients")
struct ChatsAndPushAPIClientTests {
  @Test("Fetches every page of conversation summaries")
  func conversationIndex() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chats-page-1"),
      try .http(fixture: "chats-page-2")
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)

    let conversations = try await client.fetchAll()

    #expect(conversations.map(\.title) == [
      "Where did my money go this month?",
      "Can I afford a trip?",
      "Find recurring costs"
    ])
    #expect((await stub.requests()).compactMap(pageQueryValue) == [1, 2])
  }

  @Test("Loads every page of an existing conversation")
  func conversationDetail() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chat-page-1"),
      try .http(fixture: "chat-page-2-stale")
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)
    let chatID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000701"))

    let conversation = try await client.fetch(id: chatID)

    #expect(conversation.messages.count == 21)
    #expect(conversation.messages.last?.content == "The previous latest response.")
    #expect((await stub.requests()).compactMap(pageQueryValue) == [1, 2])
  }

  @Test("Creates a chat with a typed request and documented response")
  func createChat() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chat-empty", status: 201)
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)
    let chatID = try await client.create(title: "Sure for Apple")

    #expect(chatID.uuidString == "00000000-0000-4000-8000-000000000701")
    let request = try #require((await stub.requests()).first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/v1/chats")
    let body = try JSONDecoder().decode(ChatTitleBody.self, from: try #require(request.httpBody))
    #expect(body.title == "Sure for Apple")
  }

  @Test("Rejects a malformed successful chat creation response")
  func malformedChatCreation() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"id":"not-a-uuid"}"#, status: 201)
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)

    do {
      _ = try await client.create(title: "Sure for Apple")
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .decoding)
    }
  }

  @Test("Maps chat creation validation failures")
  func chatCreationValidationFailure() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "error-validation", status: 422)
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)

    do {
      _ = try await client.create(title: "")
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .validation)
    }
  }

  @Test("Polls typed chat messages without sleeping in tests")
  func sendMessage() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chat-empty"),
      try .http(fixture: "chat-message-submission", status: 201),
      try .http(fixture: "chat-with-reply")
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)
    let chatID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000701"))
    let reply = try await client.sendMessage("How am I doing?", chatID: chatID)

    #expect(reply == "Your typed Sure response.")
    let requests = await stub.requests()
    #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET"])
    #expect(requests[1].url?.path == "/api/v1/chats/00000000-0000-4000-8000-000000000701/messages")
    let body = try JSONDecoder().decode(ChatMessageBody.self, from: try #require(requests[1].httpBody))
    #expect(body.content == "How am I doing?")
  }

  @Test("Excludes stale replies and follows the injected polling delay")
  func delayedReply() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chat-stale-reply"),
      try .http(fixture: "chat-message-submission", status: 201),
      try .http(fixture: "chat-stale-reply"),
      try .http(fixture: "chat-with-reply")
    ])
    let recorder = PollingSleepRecorder()
    let policy = ChatPollingPolicy(
      maximumAttempts: 2,
      delay: .seconds(3),
      sleep: { delay in await recorder.record(delay) }
    )
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: policy)
    let chatID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000701"))

    #expect(try await client.sendMessage("How am I doing?", chatID: chatID) == "Your typed Sure response.")
    #expect(await recorder.delays() == [.seconds(3)])
    #expect((await stub.requests()).map(\.httpMethod) == ["GET", "POST", "GET", "GET"])
  }

  @Test("Polls the latest page of a long chat")
  func paginatedChat() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chat-page-1"),
      try .http(fixture: "chat-page-2-stale"),
      try .http(fixture: "chat-message-submission", status: 201),
      try .http(fixture: "chat-page-1"),
      try .http(fixture: "chat-page-2-new-reply")
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)
    let chatID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000701"))

    #expect(try await client.sendMessage("How am I doing?", chatID: chatID) == "Your typed Sure response.")
    let requests = await stub.requests()
    #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "GET", "GET"])
    #expect(requests.compactMap(pageQueryValue) == [1, 2, 1, 2])
  }

  @Test("Bounds polling and reports a timeout")
  func responseTimeout() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chat-empty"),
      try .http(fixture: "chat-message-submission", status: 201),
      try .http(fixture: "chat-empty"),
      try .http(fixture: "chat-empty")
    ])
    let client = ChatsAPIClient(
      transport: makeTransport(stub),
      pollingPolicy: ChatPollingPolicy(
        maximumAttempts: 2,
        delay: .zero,
        sleep: { _ in }
      )
    )
    let chatID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000701"))

    do {
      _ = try await client.sendMessage("How am I doing?", chatID: chatID)
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .responseTimeout)
    }
    #expect((await stub.requests()).count == 4)
  }

  @Test("Redacts backend response details")
  func backendFailure() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chat-empty"),
      try .http(fixture: "chat-message-failed", status: 201)
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)
    let chatID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000701"))

    do {
      _ = try await client.sendMessage("How am I doing?", chatID: chatID)
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .backend)
      #expect(!error.localizedDescription.contains("Synthetic provider detail"))
    }
  }

  @Test("Rejects a malformed successful message submission response")
  func malformedMessageSubmission() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chat-empty"),
      try .http(json: #"{"id":"not-a-uuid"}"#, status: 201)
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)
    let chatID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000701"))

    do {
      _ = try await client.sendMessage("How am I doing?", chatID: chatID)
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .decoding)
    }
    #expect((await stub.requests()).map(\.httpMethod) == ["GET", "POST"])
  }

  @Test("Maps message submission validation failures")
  func messageSubmissionValidationFailure() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "chat-empty"),
      try .http(fixture: "error-validation", status: 422)
    ])
    let client = ChatsAPIClient(transport: makeTransport(stub), pollingPolicy: noDelayPolicy)
    let chatID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000701"))

    do {
      _ = try await client.sendMessage("", chatID: chatID)
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .validation)
    }
    #expect((await stub.requests()).map(\.httpMethod) == ["GET", "POST"])
  }

  @Test("Registers and unregisters a typed push subscription")
  func pushSubscription() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "push-subscription-success", status: 201),
      try .http(status: 204)
    ])
    let client = PushSubscriptionsAPIClient(transport: makeTransport(stub))
    let deviceKey = String(repeating: "ab", count: 32)
    let identifier = try await client.register(token: "synthetic-device-token", environment: .sandbox, deviceKey: deviceKey)
    try await client.unregister(id: identifier)

    #expect(identifier.uuidString == "00000000-0000-4000-8000-000000000801")
    let requests = await stub.requests()
    #expect(requests.map(\.httpMethod) == ["POST", "DELETE"])
    #expect(requests[1].url?.path == "/api/v1/push_subscriptions/00000000-0000-4000-8000-000000000801")
    let body = try JSONDecoder().decode(PushBody.self, from: try #require(requests[0].httpBody))
    #expect(body.token == "synthetic-device-token")
    #expect(body.environment == "sandbox")
    #expect(body.platform == "ios")
    #expect(body.device_key == deviceKey)
  }

  @Test("Rejects a malformed successful push registration response")
  func malformedPushRegistration() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"id":"not-a-uuid"}"#, status: 201)
    ])
    let client = PushSubscriptionsAPIClient(transport: makeTransport(stub))

    do {
      _ = try await client.register(token: "synthetic-device-token", environment: .sandbox)
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .decoding)
    }
  }

  @Test("Maps push registration validation failures")
  func pushRegistrationValidationFailure() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "error-validation", status: 422)
    ])
    let client = PushSubscriptionsAPIClient(transport: makeTransport(stub))

    do {
      _ = try await client.register(token: "", environment: .sandbox)
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .validation)
    }
  }

  @Test("Preserves DELETE 404 for idempotent lifecycle cleanup")
  func missingPushSubscription() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "error-validation", status: 404)
    ])
    let client = PushSubscriptionsAPIClient(transport: makeTransport(stub))
    let identifier = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000801"))

    do {
      try await client.unregister(id: identifier)
      #expect(Bool(false))
    } catch let error as SureAPIError {
      // NotificationManager treats this typed result as successful idempotent cleanup.
      #expect(error == .notFound)
    }
  }

  private var noDelayPolicy: ChatPollingPolicy {
    ChatPollingPolicy(maximumAttempts: 1, delay: .zero, sleep: { _ in })
  }

  private func makeTransport(_ stub: HTTPDataTransportStub) -> SureAPITransport {
    SureAPITransport(
      baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer()
    )
  }

  private func pageQueryValue(_ request: URLRequest) -> Int? {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let value = components.queryItems?.first(where: { $0.name == "page" })?.value else {
      return nil
    }
    return Int(value)
  }
}

private struct ChatTitleBody: Decodable {
  var title: String
}

private struct ChatMessageBody: Decodable {
  var content: String
}

private struct PushBody: Decodable {
  var token: String
  var environment: String
  var platform: String
  var device_key: String?
}

private actor PollingSleepRecorder {
  private var recordedDelays: [Duration] = []

  func record(_ delay: Duration) {
    recordedDelays.append(delay)
  }

  func delays() -> [Duration] {
    recordedDelays
  }
}
