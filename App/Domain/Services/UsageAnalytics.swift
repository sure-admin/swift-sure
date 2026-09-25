/// Closed event vocabulary: no financial data, identifiers, URLs, or free-form text.
@MainActor
protocol UsageAnalytics: AnyObject {
  func capture(_ event: UsageEvent)
  func resetIdentity()
}

enum UsageEvent: Equatable {
  case appOpened
  case screenViewed(UsageScreen)
  case welcomePageViewed(variant: WelcomeVariant, pitch: WelcomePitch)
  case welcomeAction(variant: WelcomeVariant, pitch: WelcomePitch, action: WelcomeAction)
  case welcomeOutcome(variant: WelcomeVariant, outcome: WelcomeOutcome)
  case financeKitSyncFailed(operation: FinanceKitSyncOperation, category: FinanceKitSyncFailureCategory)

  var name: String {
    switch self {
    case .appOpened: "app_opened"
    case .screenViewed: "screen_viewed"
    case .welcomePageViewed: "welcome_page_viewed"
    case .welcomeAction: "welcome_action"
    case .welcomeOutcome: "welcome_outcome"
    case .financeKitSyncFailed: "financekit_sync_failed"
    }
  }

  var properties: [String: String] {
    switch self {
    case .appOpened: [:]
    case .screenViewed(let screen): ["screen": screen.rawValue]
    case .welcomePageViewed(let variant, let pitch):
      ["variant": variant.rawValue, "pitch": pitch.rawValue]
    case .welcomeAction(let variant, let pitch, let action):
      ["variant": variant.rawValue, "pitch": pitch.rawValue, "action": action.rawValue]
    case .welcomeOutcome(let variant, let outcome):
      ["variant": variant.rawValue, "outcome": outcome.rawValue]
    case .financeKitSyncFailed(let operation, let category):
      ["operation": operation.rawValue, "category": category.rawValue]
    }
  }
}

enum WelcomeVariant: String {
  case instantReveal, storyCards, heroOverview
}

enum WelcomePitch: String {
  case wallet, demo
}

enum WelcomeAction: String {
  case connectWallet, exploreDemo
}

enum WelcomeOutcome: String {
  case walletConnected, walletDeclined, demoConnected
}

enum FinanceKitSyncOperation: String {
  case sync, status, enroll, repair, renew, disconnect
}

enum FinanceKitSyncFailureCategory: String {
  case invalidAmount, invalidCheckpoint, invalidReceipt, invalidState
  case historyTokenInvalid, unsupportedSourceValue, eventTooLarge, sequenceExhausted, streamFailed
  case rejected, conflict, authentication, authorization, publisherRevoked, rateLimited, server, tooLarge
  case invalidResponse, transport, other
}

enum UsageScreen: String, CaseIterable {
  case overview, assistant, accounts, budget
  case connectionSettings = "connection_settings"
  case signIn = "sign_in"
  case onboarding
}
