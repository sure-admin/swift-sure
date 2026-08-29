import Foundation
import Testing
@testable import Sure

@Suite("Budgets API client")
struct BudgetsAPIClientTests {
  @Test("Paginates budgets and categories, then hydrates every category detail")
  func paginationSelectionAndDetailHydration() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "budgets-page-1"),
      try .http(fixture: "budgets-page-2"),
      try .http(fixture: "budget-categories-page-1"),
      try .http(fixture: "budget-categories-page-2"),
      try .http(fixture: "budget-category-groceries-detail"),
      try .http(fixture: "budget-category-housing-detail")
    ])

    let records = try await makeClient(stub).fetchCurrentBudgetCategories()

    #expect(records.map(\.id.uuidString) == [
      "00000000-0000-4000-8000-000000000611",
      "00000000-0000-4000-8000-000000000612"
    ])
    #expect(records.map(\.name) == ["Groceries", "Housing"])
    let usd = try #require(CurrencyCode("USD"))
    #expect(records[0].spent == Money(
      minorUnits: 12_345,
      currency: usd
    ))
    #expect(records[1].limit.minorUnits == 70_000)
    #expect(records.allSatisfy { $0.spent.currency == $0.limit.currency })

    let requests = await stub.requests()
    #expect(requests.count == 6)
    #expect(requests.map { $0.url?.path } == [
      "/api/v1/budgets",
      "/api/v1/budgets",
      "/api/v1/budget_categories",
      "/api/v1/budget_categories",
      "/api/v1/budget_categories/00000000-0000-4000-8000-000000000611",
      "/api/v1/budget_categories/00000000-0000-4000-8000-000000000612"
    ])
    #expect(queryValue("page", in: requests[0]) == "1")
    #expect(queryValue("page", in: requests[1]) == "2")
    #expect(queryValue("per_page", in: requests[0]) == "100")
    #expect(queryValue("budget_id", in: requests[2]) ==
      "00000000-0000-4000-8000-000000000602")
    #expect(queryValue("page", in: requests[2]) == "1")
    #expect(queryValue("page", in: requests[3]) == "2")
    #expect(queryValue("per_page", in: requests[3]) == "100")
    #expect(requests[4].url?.query == nil)
    #expect(requests.allSatisfy { $0.httpMethod == "GET" })
  }

  @Test("An empty budget collection is a successful empty result")
  func emptyBudgets() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "budgets-empty")])
    let records = try await makeClient(stub).fetchCurrentBudgetCategories()
    #expect(records.isEmpty)
    #expect(await stub.requests().count == 1)
  }

  @Test("A family with no current budget does not load categories")
  func noCurrentBudget() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "budgets-no-current")])
    let records = try await makeClient(stub).fetchCurrentBudgetCategories()
    #expect(records.isEmpty)
    #expect(await stub.requests().count == 1)
  }

  @Test("A current budget with no categories is a successful empty result")
  func emptyCategories() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: currentBudgetCollectionJSON),
      try .http(fixture: "budget-categories-empty")
    ])
    let records = try await makeClient(stub).fetchCurrentBudgetCategories()
    #expect(records.isEmpty)
    #expect(await stub.requests().count == 2)
  }

  @Test("Multiple current budgets fail instead of selecting arbitrarily")
  func multipleCurrentBudgets() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "budgets-multiple-current")])
    await #expect(throws: SureAPIError.decoding) {
      _ = try await makeClient(stub).fetchCurrentBudgetCategories()
    }
    #expect(await stub.requests().count == 1)
  }

  @Test("A budget missing its required currency fails the collection")
  func malformedBudget() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "budgets-malformed")])
    await #expect(throws: SureAPIError.decoding) {
      _ = try await makeClient(stub).fetchCurrentBudgetCategories()
    }
  }

  @Test("A category detail without exact minor units fails the collection")
  func malformedCategoryDetail() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: currentBudgetCollectionJSON),
      try .http(json: singleCategoryCollectionJSON),
      try .http(fixture: "budget-category-malformed-detail")
    ])
    await #expect(throws: SureAPIError.decoding) {
      _ = try await makeClient(stub).fetchCurrentBudgetCategories()
    }
  }

  @Test("A category summary without its server ID fails instead of inventing one")
  func malformedCategorySummary() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: currentBudgetCollectionJSON),
      try .http(fixture: "budget-categories-malformed")
    ])
    await #expect(throws: SureAPIError.decoding) {
      _ = try await makeClient(stub).fetchCurrentBudgetCategories()
    }
  }

  @Test("Category collection authorization failures remain distinct")
  func categoryAuthorizationFailure() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: currentBudgetCollectionJSON),
      try .http(fixture: "error-insufficient-scope", status: 403)
    ])
    await #expect(throws: SureAPIError.forbidden) {
      _ = try await makeClient(stub).fetchCurrentBudgetCategories()
    }
  }

  private func makeClient(_ stub: HTTPDataTransportStub) -> BudgetsAPIClient {
    BudgetsAPIClient(transport: SureAPITransport(
      baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer()
    ))
  }

  private func queryValue(_ name: String, in request: URLRequest) -> String? {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    return components.queryItems?.first { $0.name == name }?.value
  }

  private var currentBudgetCollectionJSON: String {
    """
    {
      "budgets": [{
        "id": "00000000-0000-4000-8000-000000000602",
        "start_date": "2026-08-01",
        "end_date": "2026-08-31",
        "name": "August 2026",
        "currency": "USD",
        "initialized": true,
        "current": true,
        "allocated_spending": "$1,200.00",
        "allocated_spending_cents": 120000,
        "created_at": "2026-07-20T10:00:00Z",
        "updated_at": "2026-08-28T18:00:00Z"
      }],
      "pagination": {
        "page": 1, "per_page": 100, "total_count": 1, "total_pages": 1
      }
    }
    """
  }

  private var singleCategoryCollectionJSON: String {
    """
    {
      "budget_categories": [{
        "id": "00000000-0000-4000-8000-000000000611",
        "budget_id": "00000000-0000-4000-8000-000000000602",
        "currency": "USD",
        "category": {
          "id": "00000000-0000-4000-8000-000000000621",
          "name": "Groceries"
        }
      }],
      "pagination": {
        "page": 1, "per_page": 100, "total_count": 1, "total_pages": 1
      }
    }
    """
  }
}
