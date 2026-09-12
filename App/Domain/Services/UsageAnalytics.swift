/// Closed event vocabulary: no financial data, identifiers, URLs, or free-form text.
@MainActor
protocol UsageAnalytics: AnyObject {
  func capture(_ event: UsageEvent)
  func resetIdentity()
}

enum UsageEvent: Equatable {
  case appOpened
  case screenViewed(UsageScreen)

  var name: String {
    switch self {
    case .appOpened: "app_opened"
    case .screenViewed: "screen_viewed"
    }
  }

  var properties: [String: String] {
    switch self {
    case .appOpened: [:]
    case .screenViewed(let screen): ["screen": screen.rawValue]
    }
  }
}

enum UsageScreen: String, CaseIterable {
  case overview, assistant, accounts, budget
  case connectionSettings = "connection_settings"
  case signIn = "sign_in"
  case onboarding
}
