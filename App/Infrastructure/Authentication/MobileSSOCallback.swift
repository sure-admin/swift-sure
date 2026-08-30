import Foundation

enum MobileSSOCallback: Equatable, Sendable {
  case authorizationCode(String)
  case onboarding(MobileSSOOnboardingContext)

  static func parse(_ url: URL) throws -> Self {
    guard url.scheme == "sureapp",
          url.host == "oauth",
          url.path == "/callback",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw MobileSSOError.invalidCallback
    }
    let values = Dictionary(
      components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
      uniquingKeysWith: { first, _ in first }
    )
    if let error = values["error"] {
      if error == "invalid_provider" || error == "sso_provider_unavailable" {
        throw MobileSSOError.providerUnavailable
      }
      if error == "sso_invalid_response" {
        throw MobileSSOError.invalidProviderResponse
      }
      throw MobileSSOError.signInFailed
    }
    if let code = values["code"], !code.isEmpty {
      return .authorizationCode(code)
    }
    guard values["status"] == "account_not_linked",
          let linkingCode = values["linking_code"],
          !linkingCode.isEmpty else {
      throw MobileSSOError.invalidCallback
    }
    return .onboarding(MobileSSOOnboardingContext(
      linkingCode: linkingCode,
      email: values["email"].flatMap(\.nilIfEmpty),
      firstName: values["first_name"].flatMap(\.nilIfEmpty),
      lastName: values["last_name"].flatMap(\.nilIfEmpty),
      allowsAccountCreation: values["allow_account_creation"] == "true",
      hasPendingInvitation: values["has_pending_invitation"] == "true"
    ))
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
