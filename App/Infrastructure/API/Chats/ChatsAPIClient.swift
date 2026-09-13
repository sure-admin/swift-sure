import Foundation

struct ChatsAPIClient {
  var transport: SureAPITransport
  var pollingPolicy: ChatPollingPolicy

  func fetchAll() async throws -> [ChatSummaryDTO] {
    var page = 1
    var records: [ChatSummaryDTO] = []
    var expectedTotalCount: Int?
    var expectedTotalPages: Int?

    while true {
      let request = APIRequest<ChatCollectionDTO>(
        method: .get,
        pathComponents: ["api", "v1", "chats"],
        queryItems: [URLQueryItem(name: "page", value: String(page))],
        forbiddenResponse: .featureUnavailable
      )
      let collection = try await transport.send(request)
      try validate(
        collection.pagination,
        requestedPage: page,
        itemCount: collection.chats.count,
        expectedTotalCount: expectedTotalCount,
        expectedTotalPages: expectedTotalPages
      )
      expectedTotalCount = collection.pagination.totalCount
      expectedTotalPages = collection.pagination.totalPages
      records.append(contentsOf: collection.chats)

      guard page < collection.pagination.totalPages else {
        guard records.count == collection.pagination.totalCount else {
          throw SureAPIError.decoding
        }
        return records
      }
      page += 1
    }
  }

  func fetch(id: UUID) async throws -> ChatDetailDTO {
    let firstPage = try await fetchChat(chatID: id, page: 1)
    guard let pagination = firstPage.pagination else { throw SureAPIError.decoding }
    try validateDetailPage(
      firstPage,
      requestedPage: 1,
      expectedChatID: id,
      expectedPagination: pagination
    )
    var messages = firstPage.messages

    if pagination.totalPages > 1 {
      for page in 2...pagination.totalPages {
        let response = try await fetchChat(chatID: id, page: page)
        try validateDetailPage(
          response,
          requestedPage: page,
          expectedChatID: id,
          expectedPagination: pagination
        )
        messages.append(contentsOf: response.messages)
      }
    }
    guard messages.count == pagination.totalCount else { throw SureAPIError.decoding }

    return ChatDetailDTO(
      id: firstPage.id,
      title: firstPage.title,
      error: firstPage.error,
      createdAt: firstPage.createdAt,
      updatedAt: firstPage.updatedAt,
      messages: messages,
      pagination: pagination
    )
  }

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
        try await pollingPolicy.sleep(pollingPolicy.delay(beforeAttempt: attempt))
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

  private func validate(
    _ pagination: PaginationDTO,
    requestedPage: Int,
    itemCount: Int,
    expectedTotalCount: Int?,
    expectedTotalPages: Int?
  ) throws {
    guard pagination.page == requestedPage,
          pagination.perPage > 0,
          pagination.totalCount >= 0,
          pagination.totalPages >= 1,
          itemCount <= pagination.perPage,
          expectedTotalCount == nil || pagination.totalCount == expectedTotalCount,
          expectedTotalPages == nil || pagination.totalPages == expectedTotalPages else {
      throw SureAPIError.decoding
    }
  }

  private func validateDetailPage(
    _ response: ChatDetailDTO,
    requestedPage: Int,
    expectedChatID: UUID,
    expectedPagination: PaginationDTO
  ) throws {
    guard let pagination = response.pagination,
          response.id == expectedChatID,
          pagination.page == requestedPage,
          pagination.perPage > 0,
          pagination.totalCount == expectedPagination.totalCount,
          pagination.totalPages == expectedPagination.totalPages,
          pagination.totalPages >= 1,
          response.messages.count <= pagination.perPage else {
      throw SureAPIError.decoding
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
