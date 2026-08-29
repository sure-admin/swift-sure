import Foundation

struct BudgetsAPIClient {
  var transport: SureAPITransport

  func fetchCurrentBudgetCategories() async throws -> [BudgetCategoryRecord] {
    let budgets = try await fetchAllBudgets()
    let currentBudgets = budgets.filter(\.current)
    guard currentBudgets.count <= 1 else {
      throw SureAPIError.decoding
    }
    guard let budget = currentBudgets.first else {
      return []
    }
    guard CurrencyCode(budget.currency) != nil else {
      throw SureAPIError.decoding
    }

    let summaries = try await fetchAllCategorySummaries(for: budget.id)
    var records: [BudgetCategoryRecord] = []
    records.reserveCapacity(summaries.count)
    // Keep detail hydration bounded to one request at a time. A current budget
    // can contain many categories, and this read path must not fan out an
    // unbounded burst against a self-hosted Sure instance.
    for summary in summaries {
      try Task.checkCancellation()
      let detail = try await fetchCategoryDetail(summary.id)
      records.append(try detail.budgetCategoryRecord(matching: summary, budget: budget))
    }
    return records
  }

  private func fetchAllBudgets() async throws -> [BudgetDTO] {
    var page = 1
    var expectedTotalCount: Int?
    var expectedTotalPages: Int?
    var budgets: [BudgetDTO] = []

    while true {
      try Task.checkCancellation()
      let collection = try await transport.send(
        APIRequest<BudgetCollectionDTO>(
          method: .get,
          pathComponents: ["api", "v1", "budgets"],
          queryItems: Self.paginationQueryItems(page: page)
        )
      )
      try validate(
        collection.pagination,
        itemCount: collection.budgets.count,
        requestedPage: page,
        expectedTotalCount: expectedTotalCount,
        expectedTotalPages: expectedTotalPages
      )
      if expectedTotalCount == nil {
        expectedTotalCount = collection.pagination.totalCount
        expectedTotalPages = collection.pagination.totalPages
      }
      budgets.append(contentsOf: collection.budgets)
      guard page < collection.pagination.totalPages else {
        guard budgets.count == collection.pagination.totalCount,
              Set(budgets.map(\.id)).count == budgets.count else {
          throw SureAPIError.decoding
        }
        return budgets
      }
      page += 1
    }
  }

  private func fetchAllCategorySummaries(
    for budgetID: UUID
  ) async throws -> [BudgetCategorySummaryDTO] {
    var page = 1
    var expectedTotalCount: Int?
    var expectedTotalPages: Int?
    var summaries: [BudgetCategorySummaryDTO] = []

    while true {
      try Task.checkCancellation()
      let collection = try await transport.send(
        APIRequest<BudgetCategoryCollectionDTO>(
          method: .get,
          pathComponents: ["api", "v1", "budget_categories"],
          queryItems: [
            URLQueryItem(name: "budget_id", value: budgetID.uuidString.lowercased())
          ] + Self.paginationQueryItems(page: page)
        )
      )
      try validate(
        collection.pagination,
        itemCount: collection.budgetCategories.count,
        requestedPage: page,
        expectedTotalCount: expectedTotalCount,
        expectedTotalPages: expectedTotalPages
      )
      if expectedTotalCount == nil {
        expectedTotalCount = collection.pagination.totalCount
        expectedTotalPages = collection.pagination.totalPages
      }
      summaries.append(contentsOf: collection.budgetCategories)
      guard page < collection.pagination.totalPages else {
        guard summaries.count == collection.pagination.totalCount,
              Set(summaries.map(\.id)).count == summaries.count,
              summaries.allSatisfy({ $0.budgetID == budgetID }) else {
          throw SureAPIError.decoding
        }
        return summaries
      }
      page += 1
    }
  }

  private func fetchCategoryDetail(_ id: UUID) async throws -> BudgetCategoryDetailDTO {
    try await transport.send(
      APIRequest<BudgetCategoryDetailDTO>(
        method: .get,
        pathComponents: [
          "api", "v1", "budget_categories", id.uuidString.lowercased()
        ]
      )
    )
  }

  private func validate(
    _ pagination: PaginationDTO,
    itemCount: Int,
    requestedPage: Int,
    expectedTotalCount: Int?,
    expectedTotalPages: Int?
  ) throws {
    guard pagination.page == requestedPage,
          pagination.perPage > 0,
          pagination.perPage <= Self.pageSize,
          pagination.totalCount >= 0,
          pagination.totalPages >= 0,
          itemCount <= pagination.perPage,
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
      guard requestedPage == 1, itemCount == 0 else {
        throw SureAPIError.decoding
      }
    } else {
      guard requestedPage <= pagination.totalPages, itemCount > 0 else {
        throw SureAPIError.decoding
      }
    }
  }

  private static func paginationQueryItems(page: Int) -> [URLQueryItem] {
    [
      URLQueryItem(name: "per_page", value: String(pageSize)),
      URLQueryItem(name: "page", value: String(page))
    ]
  }

  private static let pageSize = 100
}
