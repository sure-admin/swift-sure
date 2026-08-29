import Foundation
import Testing
@testable import Sure

@Suite("Budget category")
struct BudgetCategoryTests {
  @Test("Progress divides spending by the limit")
  func progress() {
    let currency = CurrencyCode("USD")!
    let category = BudgetCategory(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
      name: "Groceries",
      symbol: "cart.fill",
      spent: Money(minorUnits: 12_500, currency: currency),
      limit: Money(minorUnits: 50_000, currency: currency)
    )

    #expect(category.progress == 0.25)
  }

  @Test("A zero limit has zero progress")
  func zeroLimit() {
    let currency = CurrencyCode("JPY")!
    let category = BudgetCategory(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
      name: "Unallocated",
      symbol: "tray.fill",
      spent: Money(minorUnits: 125, currency: currency),
      limit: Money(minorUnits: 0, currency: currency)
    )

    #expect(category.progress == 0)
  }
}
