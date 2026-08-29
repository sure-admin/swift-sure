import Foundation

struct TransactionsAPIClient {
  var transport: SureAPITransport

  func fetchAll(query: TransactionQuery = TransactionQuery()) async throws -> [TransactionRecord] {
    var page = 1
    var expectedTotalCount: Int?
    var expectedTotalPages: Int?
    var records: [TransactionRecord] = []

    while true {
      try Task.checkCancellation()
      let request = APIRequest<TransactionCollectionDTO>(
        method: .get,
        pathComponents: ["api", "v1", "transactions"],
        queryItems: query.queryItems(page: page, perPage: 100)
      )
      let response = try await transport.send(request)
      try validate(
        response,
        requestedPage: page,
        expectedTotalCount: expectedTotalCount,
        expectedTotalPages: expectedTotalPages
      )
      if expectedTotalCount == nil {
        expectedTotalCount = response.pagination.totalCount
        expectedTotalPages = response.pagination.totalPages
      }
      records += try response.transactions.map(Self.map)
      guard page < response.pagination.totalPages else {
        guard records.count == response.pagination.totalCount else {
          throw SureAPIError.decoding
        }
        return records
      }
      page += 1
    }
  }

  private func validate(
    _ collection: TransactionCollectionDTO,
    requestedPage: Int,
    expectedTotalCount: Int?,
    expectedTotalPages: Int?
  ) throws {
    let pagination = collection.pagination
    guard pagination.page == requestedPage,
          pagination.perPage > 0,
          pagination.perPage <= 100,
          pagination.totalCount >= 0,
          pagination.totalPages >= 0,
          collection.transactions.count <= pagination.perPage,
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
      guard requestedPage == 1, collection.transactions.isEmpty else {
        throw SureAPIError.decoding
      }
    } else {
      guard requestedPage <= pagination.totalPages,
            !collection.transactions.isEmpty else {
        throw SureAPIError.decoding
      }
    }
  }

  private static func map(_ dto: TransactionCollectionDTO.TransactionDTO) throws -> TransactionRecord {
    guard let currency = CurrencyCode(dto.currency),
          let classification = TransactionClassification(rawValue: dto.classification.lowercased()) else {
      throw SureAPIError.decoding
    }

    // The pinned serializer emits these exact signed minor units although the
    // generated OpenAPI currently documents only the formatted amount string.
    let signedMinorUnits: Int64
    if let value = dto.signedAmountCents {
      signedMinorUnits = value
    } else if let value = dto.amountCents {
      guard value != Int64.min else {
        throw SureAPIError.decoding
      }
      signedMinorUnits = classification == .income ? value : -value
    } else {
      throw SureAPIError.decoding
    }

    guard signedMinorUnits != Int64.min else {
      throw SureAPIError.decoding
    }
    switch classification {
    case .income:
      guard signedMinorUnits >= 0 else { throw SureAPIError.decoding }
    case .expense:
      guard signedMinorUnits <= 0 else { throw SureAPIError.decoding }
    }

    return TransactionRecord(
      id: dto.id,
      accountID: dto.account.id,
      name: dto.name,
      categoryName: dto.category?.name,
      merchantName: dto.merchant?.name,
      date: dto.date,
      signedAmount: Money(minorUnits: signedMinorUnits, currency: currency),
      classification: classification
    )
  }
}
