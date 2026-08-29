import Foundation

struct ChatsAPIClient {
  var transport: SureAPITransport
  var pollingPolicy: ChatPollingPolicy

  func create(title: String) async throws -> UUID {
    let request = APIRequest<ChatDetailDTO>(
      method: .post,
      pathComponents: ["api", "v1", "chats"],
      body: CreateChatRequest(title: title),
      expectedStatusCodes: [201],
      forbiddenResponse: .featureUnavailable
    )
    return try await transport.send(request).id
  }

  func sendMessage(_ content: String, chatID: UUID) async throws -> String {
    let existingReplyIDs = Set(try await assistantReplies(chatID: chatID).map(\.id))
    let request = APIRequest<MessageResponseDTO>(
      method: .post,
      pathComponents: ["api", "v1", "chats", chatID.uuidString.lowercased(), "messages"],
      body: CreateMessageRequest(content: content),
      expectedStatusCodes: [201],
      forbiddenResponse: .featureUnavailable
    )
    let submission = try await transport.send(request)
    if submission.aiResponseStatus == .failed {
      throw SureAPIError.backend
    }

    for attempt in 0..<pollingPolicy.maximumAttempts {
      try Task.checkCancellation()
      if attempt > 0 {
        try await pollingPolicy.sleep(pollingPolicy.delay)
      }
      if let reply = try await assistantReplies(chatID: chatID).last(where: { reply in
        !existingReplyIDs.contains(reply.id)
          && !reply.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) {
        return reply.content
      }
    }
    throw SureAPIError.responseTimeout
  }

  private func assistantReplies(chatID: UUID) async throws -> [AssistantReply] {
    let firstPage = try await fetchChat(chatID: chatID, page: 1)
    guard let firstPagination = firstPage.pagination,
          firstPagination.page == 1,
          firstPagination.totalCount >= 0,
          firstPagination.totalPages >= 1 else {
      throw SureAPIError.decoding
    }
    try checkBackendError(firstPage)

    let latestPage: ChatDetailDTO
    if firstPagination.totalPages > 1 {
      latestPage = try await fetchChat(
        chatID: chatID,
        page: firstPagination.totalPages
      )
      guard let pagination = latestPage.pagination,
            pagination.page == firstPagination.totalPages,
            pagination.totalCount >= 0,
            pagination.totalPages >= pagination.page else {
        throw SureAPIError.decoding
      }
      try checkBackendError(latestPage)
    } else {
      latestPage = firstPage
    }

    return latestPage.messages
      .filter { $0.role == .assistant }
      .map { AssistantReply(id: $0.id, content: $0.content) }
  }

  private func fetchChat(chatID: UUID, page: Int) async throws -> ChatDetailDTO {
    let request = APIRequest<ChatDetailDTO>(
      method: .get,
      pathComponents: ["api", "v1", "chats", chatID.uuidString.lowercased()],
      queryItems: [URLQueryItem(name: "page", value: String(page))],
      forbiddenResponse: .featureUnavailable
    )
    return try await transport.send(request)
  }

  private func checkBackendError(_ response: ChatDetailDTO) throws {
    if let error = response.error, !error.isEmpty {
      throw SureAPIError.backend
    }
  }
}

private struct CreateChatRequest: Encodable {
  var title: String
}

private struct CreateMessageRequest: Encodable {
  var content: String
}

private struct AssistantReply {
  var id: UUID
  var content: String
}
