import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit decimal encoding")
struct FinanceKitDecimalEncoderTests {
  @Test("Money stays an unsigned exact decimal string")
  func exactMoney() throws {
    let encoder = FinanceKitDecimalEncoder()
    #expect(try encoder.money(amount: 0, currency: "JPY", direction: .debit).amount == "0")
    #expect(try encoder.money(amount: Decimal(string: "123456789.1200")!, currency: "USD", direction: .credit).amount == "123456789.12")
    #expect(try encoder.money(amount: Decimal(string: "1.2345")!, currency: "BHD", direction: .debit).amount == "1.2345")
  }

  @Test("Direction cannot be smuggled into a negative magnitude or rounded precision")
  func rejectsInvalidMagnitude() {
    let encoder = FinanceKitDecimalEncoder()
    #expect(throws: FinanceKitSyncError.invalidAmount) {
      try encoder.money(amount: -1, currency: "USD", direction: .credit)
    }
    #expect(throws: FinanceKitSyncError.invalidAmount) {
      try encoder.money(amount: Decimal(string: "1.00001")!, currency: "USD", direction: .debit)
    }
  }
}
