import Foundation

@MainActor
struct UserDefaultsDiagnosticsPreferences: DiagnosticsPreferences {
  var defaults: UserDefaults

  var diagnosticsEnabled: Bool {
    get { (defaults.object(forKey: "sureDiagnosticsEnabled") as? Bool) ?? true }
    set { defaults.set(newValue, forKey: "sureDiagnosticsEnabled") }
  }
}
