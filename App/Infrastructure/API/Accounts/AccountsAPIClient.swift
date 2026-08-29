import Foundation

struct AccountsAPIClient {
  var transport: SureAPITransport

  func verifyAccess() async throws {
    _ = try await fetchPage(1, perPage: 1)
  }

  func fetchAll() async throws -> [AccountRecord] {
    var requestedPage = 1
    var expectedTotalCount: Int?
    var expectedTotalPages: Int?
    var records: [AccountRecord] = []

    while true {
      try Task.checkCancellation()
      let collection = try await fetchPage(requestedPage, perPage: Self.pageSize)
      try validate(
        collection,
        requestedPage: requestedPage,
        expectedTotalCount: expectedTotalCount,
        expectedTotalPages: expectedTotalPages
      )

      if expectedTotalCount == nil {
        expectedTotalCount = collection.pagination.totalCount
        expectedTotalPages = collection.pagination.totalPages
      }

      records.append(contentsOf: try collection.accounts.map { try $0.accountRecord() })

      guard requestedPage < collection.pagination.totalPages else {
        guard records.count == collection.pagination.totalCount else {
          throw SureAPIError.decoding
        }
        return records
      }
      requestedPage += 1
    }
  }

  private func fetchPage(_ page: Int, perPage: Int) async throws -> AccountCollectionDTO {
    try await transport.send(
      APIRequest<AccountCollectionDTO>(
        method: .get,
        pathComponents: ["api", "v1", "accounts"],
        queryItems: [
          URLQueryItem(name: "page", value: String(page)),
          URLQueryItem(name: "per_page", value: String(perPage))
        ]
      )
    )
  }

  private func validate(
    _ collection: AccountCollectionDTO,
    requestedPage: Int,
    expectedTotalCount: Int?,
    expectedTotalPages: Int?
  ) throws {
    let pagination = collection.pagination

    guard pagination.page == requestedPage,
          pagination.perPage > 0,
          pagination.perPage <= Self.pageSize,
          pagination.totalCount >= 0,
          pagination.totalPages >= 0,
          collection.accounts.count <= pagination.perPage,
          expectedTotalCount == nil || pagination.totalCount == expectedTotalCount,
          expectedTotalPages == nil || pagination.totalPages == expectedTotalPages else {
      throw SureAPIError.decoding
    }

    let calculatedTotalPages = pagination.totalCount == 0
      ? 1
      : ((pagination.totalCount - 1) / pagination.perPage) + 1
    guard pagination.totalPages == calculatedTotalPages else {
      throw SureAPIError.decoding
    }

    if pagination.totalCount == 0 {
      guard requestedPage == 1, collection.accounts.isEmpty else {
        throw SureAPIError.decoding
      }
    } else {
      guard requestedPage <= pagination.totalPages,
            !collection.accounts.isEmpty else {
        throw SureAPIError.decoding
      }
    }
  }

  private static let pageSize = 100
}
