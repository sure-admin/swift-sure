import Foundation

struct UserDefaultsFirstRunPreferences: FirstRunPreferences, @unchecked Sendable {
  var defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func hasCompletedFirstRun() -> Bool {
    defaults.bool(forKey: StorageKey.completed)
  }

  func setHasCompletedFirstRun(_ completed: Bool) {
    defaults.set(completed, forKey: StorageKey.completed)
  }

  // Launch arguments populate UserDefaults' argument domain, so these keys are
  // read-only design switches; the app never writes them.
  func variantOverride() -> String? {
    defaults.string(forKey: StorageKey.variant)
  }

  func regionOverride() -> String? {
    defaults.string(forKey: StorageKey.region)
  }

  func alwaysShowsFirstRun() -> Bool {
    defaults.bool(forKey: StorageKey.alwaysShow)
  }

  private enum StorageKey {
    static let completed = "sureFirstRunCompleted"
    static let variant = "sureFirstRunVariant"
    static let region = "sureFirstRunRegion"
    static let alwaysShow = "sureFirstRunAlwaysShow"
  }
}
