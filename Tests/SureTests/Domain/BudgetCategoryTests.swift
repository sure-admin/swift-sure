import Testing
@testable import Sure

@Suite("Budget category")
struct BudgetCategoryTests {
  @Test("Progress divides spending by the limit")
  func progress() {
    var category = BudgetCategory(
      name: "Groceries",
      symbol: "cart.fill",
      spent: 125,
      limit: 500
    )

    #expect(category.progress == 0.25)
  }

  @Test("A zero limit has zero progress")
  func zeroLimit() {
    var category = BudgetCategory(
      name: "Unallocated",
      symbol: "tray.fill",
      spent: 125,
      limit: 0
    )

    #expect(category.progress == 0)
  }
}
