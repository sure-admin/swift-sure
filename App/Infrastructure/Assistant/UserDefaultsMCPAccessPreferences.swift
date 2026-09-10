import Foundation

@MainActor
struct UserDefaultsMCPAccessPreferences: MCPAccessPreferences {
  var defaults: UserDefaults
  private let key = "sureAssistantAllowsAutomaticMCP"

  func allowsAutomaticAccess() -> Bool { defaults.bool(forKey: key) }
  func setAllowsAutomaticAccess(_ allowed: Bool) { defaults.set(allowed, forKey: key) }
}
