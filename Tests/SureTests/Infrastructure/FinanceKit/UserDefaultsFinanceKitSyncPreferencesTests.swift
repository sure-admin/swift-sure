import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Wallet sync consent preferences")
struct UserDefaultsFinanceKitSyncPreferencesTests {
  @Test("Consent and pending withdrawal persist in an isolated preferences domain")
  func persistence() throws {
    let name = "financekit-consent-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let first = UserDefaultsFinanceKitSyncPreferences(defaults: defaults)
    #expect(first.consentAcknowledged == nil)
    first.consentAcknowledged = true
    let second = UserDefaultsFinanceKitSyncPreferences(defaults: defaults)
    #expect(second.consentAcknowledged == true)
    second.consentAcknowledged = false
    second.consentWithdrawalPending = true
    let third = UserDefaultsFinanceKitSyncPreferences(defaults: defaults)
    #expect(third.consentAcknowledged == false)
    #expect(third.consentWithdrawalPending)
  }
}
