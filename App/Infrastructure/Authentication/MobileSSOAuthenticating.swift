import Foundation

enum MobileSSOResult: Equatable, Sendable {
  case authenticated(PasskeyOAuthTokens, deviceID: String)
  case onboarding(MobileSSOOnboardingContext)
}

@MainActor
protocol MobileSSOAuthenticating {
  func signIn(
    email: String,
    password: String,
    serverURL: String
  ) async throws -> MobileSSOResult

  func signIn(
    provider: SSOProvider,
    serverURL: String
  ) async throws -> MobileSSOResult
}

extension MobileSSOAuthenticating {
  func signIn(
    email: String,
    password: String,
    serverURL: String
  ) async throws -> MobileSSOResult {
    throw MobileSSOError.couldNotStart
  }
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
