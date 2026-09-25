import Foundation

@MainActor
final class UserDefaultsFinanceKitSyncPreferences: FinanceKitSyncPreferences {
  private var defaults: UserDefaults

  init(defaults: UserDefaults) { self.defaults = defaults }

  var consentWithdrawalPending: Bool {
    get { defaults.bool(forKey: "financeKitSyncConsentWithdrawalPending") }
    set { defaults.set(newValue, forKey: "financeKitSyncConsentWithdrawalPending") }
  }

  var consentAcknowledged: Bool? {
    get { defaults.object(forKey: "financeKitSyncConsentAcknowledged") as? Bool }
    set {
      if let newValue { defaults.set(newValue, forKey: "financeKitSyncConsentAcknowledged") }
      else { defaults.removeObject(forKey: "financeKitSyncConsentAcknowledged") }
    }
  }
}
