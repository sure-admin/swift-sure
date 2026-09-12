import Foundation

@MainActor
struct UserDefaultsAnalyticsPreferences: AnalyticsPreferences {
  var defaults: UserDefaults

  var analyticsEnabled: Bool {
    get { (defaults.object(forKey: "sureUsageAnalyticsEnabled") as? Bool) ?? true }
    set { defaults.set(newValue, forKey: "sureUsageAnalyticsEnabled") }
  }
}
