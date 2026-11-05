import Foundation
import Testing
@testable import Sure

@Suite("Accounts widget selection")
struct AccountsWidgetSelectionTests {
  private let snapshot = AccountsWidgetSnapshot(
    accounts: [
      .init(id: "card", name: "Card", institution: "", balance: "-$5.00", isLiability: true),
      .init(id: "checking", name: "Checking", institution: "", balance: "$1.00", isLiability: false),
      .init(id: "savings", name: "Savings", institution: "", balance: "$2.00", isLiability: false)
    ],
    netWorth: nil,
    updatedAt: testReadDate
  )

  @Test("With nothing picked, assets come before liabilities in Sure's order")
  func allAccounts() {
    let ids = AccountsWidgetSelection.accounts(in: snapshot, pickedIDs: []).map(\.id)
    #expect(ids == ["checking", "savings", "card"])
  }

  @Test("Picked accounts appear exactly, in the picked order")
  func pickedOrder() {
    let ids = AccountsWidgetSelection.accounts(in: snapshot, pickedIDs: ["savings", "card"]).map(\.id)
    #expect(ids == ["savings", "card"])
  }

  @Test("Picked accounts missing from the snapshot and repeated picks are skipped")
  func missingAndDuplicates() {
    let ids = AccountsWidgetSelection.accounts(in: snapshot, pickedIDs: ["gone", "checking", "checking"]).map(\.id)
    #expect(ids == ["checking"])
  }
}
