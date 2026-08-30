import Foundation

enum MobileSSOResult: Equatable, Sendable {
  case authenticated(PasskeyOAuthTokens, deviceID: String)
  case onboarding(MobileSSOOnboardingContext)
}

@MainActor
protocol MobileSSOAuthenticating {
  func signIn(
    provider: SSOProvider,
    serverURL: String
  ) async throws -> MobileSSOResult
}

@MainActor
struct UnavailableMobileSSOAuthenticator: MobileSSOAuthenticating {
  func signIn(
    provider: SSOProvider,
    serverURL: String
  ) async throws -> MobileSSOResult {
    throw MobileSSOError.couldNotStart
  }
}
