import Testing
@testable import Sure

@Suite("App section navigation")
struct AppSectionTests {
  @Test("Moves between adjacent sections in display order")
  func adjacentSections() {
    #expect(AppSection.overview.moving(by: 1) == .assistant)
    #expect(AppSection.assistant.moving(by: 1) == .accounts)
    #expect(AppSection.accounts.moving(by: 1) == .budget)
    #expect(AppSection.budget.moving(by: -1) == .accounts)
  }

  @Test("Stops at the first and last sections")
  func boundaries() {
    #expect(AppSection.overview.moving(by: -1) == .overview)
    #expect(AppSection.budget.moving(by: 1) == .budget)
  }
}
