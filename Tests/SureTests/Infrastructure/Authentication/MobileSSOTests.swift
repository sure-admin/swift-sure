import Foundation
import Testing
@testable import Sure

@Suite("Mobile SSO contract")
struct MobileSSOTests {
  @Test("Registers the mobile SSO callback scheme in the app bundle")
  func callbackSchemeRegistration() throws {
    let urlTypes = try #require(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
    )
    let schemes = urlTypes.flatMap { urlType in
      urlType["CFBundleURLSchemes"] as? [String] ?? []
    }

    #expect(schemes.contains("sureapp"))
  }

  @Test("Uses the external browser and receives the app callback")
  @MainActor
  func externalBrowserCallback() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"access_token":"access-1","refresh_token":"refresh-1"}"#)
    ])
    var service: MobileSSOAuthService!
    var openedURL: URL?
    service = MobileSSOAuthService(
      httpClient: MobileSSOHTTPClient(dataTransport: stub),
      deviceInformation: testDeviceInformationProvider(),
      openURL: { url in
        openedURL = url
        Task { @MainActor in
          service.handleOpenURL(URL(string: "sureapp://oauth/callback?code=one-time-code")!)
        }
        return true
      }
    )

    let result = try await service.signIn(
      provider: .google,
      serverURL: "https://sure.example"
    )

    #expect(openedURL?.path == "/auth/mobile/google_oauth2")
    #expect(result == .authenticated(
      PasskeyOAuthTokens(accessToken: "access-1", refreshToken: "refresh-1"),
      deviceID: "00000000-0000-0000-0000-000000000123"
    ))
  }

  @Test("Reports when the system browser cannot open")
  @MainActor
  func externalBrowserFailure() async throws {
    let service = MobileSSOAuthService(
      httpClient: MobileSSOHTTPClient(dataTransport: HTTPDataTransportStub([])),
      deviceInformation: testDeviceInformationProvider(),
      openURL: { _ in false }
    )

    await #expect(throws: MobileSSOError.couldNotStart) {
      try await service.signIn(provider: .google, serverURL: "https://sure.example")
    }
  }

  @Test("Builds the provider route with required device information")
  @MainActor
  func authorizationURL() throws {
    let url = try MobileSSOAuthService.authorizationURL(
      server: OAuthServerURL("https://sure.example/self-hosted"),
      provider: .apple,
      device: MobileDeviceInformation(
        deviceID: "device-123",
        deviceName: "My iPhone & Watch",
        deviceType: "ios",
        osVersion: "26.5",
        appVersion: "0.7.4"
      )
    )
    #expect(url.path == "/self-hosted/auth/mobile/apple")
    #expect(queryValues(url) == [
      "device_id": "device-123",
      "device_name": "My iPhone & Watch",
      "device_type": "ios",
      "os_version": "26.5",
      "app_version": "0.7.4"
    ])
  }

  @Test("Parses existing-account and onboarding callbacks")
  func callbackParsing() throws {
    let authorized = try MobileSSOCallback.parse(#require(URL(
      string: "sureapp://oauth/callback?code=one-time-code"
    )))
    #expect(authorized == .authorizationCode("one-time-code"))

    let onboarding = try MobileSSOCallback.parse(#require(URL(
      string: "sureapp://oauth/callback?status=account_not_linked&linking_code=link-123&email=person%40example.com&first_name=Taylor&allow_account_creation=true&has_pending_invitation=false"
    )))
    #expect(onboarding == .onboarding(MobileSSOOnboardingContext(
      linkingCode: "link-123",
      email: "person@example.com",
      firstName: "Taylor",
      lastName: nil,
      allowsAccountCreation: true,
      hasPendingInvitation: false
    )))
  }

  @Test("Maps provider and untrusted callback errors to safe failures")
  func callbackFailures() throws {
    for error in ["invalid_provider", "sso_provider_unavailable"] {
      #expect(throws: MobileSSOError.providerUnavailable) {
        try MobileSSOCallback.parse(#require(URL(
          string: "sureapp://oauth/callback?error=\(error)&message=private"
        )))
      }
    }
    #expect(throws: MobileSSOError.invalidProviderResponse) {
      try MobileSSOCallback.parse(#require(URL(
        string: "sureapp://oauth/callback?error=sso_invalid_response&message=private"
      )))
    }
    #expect(throws: MobileSSOError.signInFailed) {
      try MobileSSOCallback.parse(#require(URL(
        string: "sureapp://oauth/callback?error=anything&message=private"
      )))
    }
    #expect(throws: MobileSSOError.invalidCallback) {
      try MobileSSOCallback.parse(#require(URL(
        string: "https://attacker.example/oauth/callback?code=secret"
      )))
    }
  }

  @Test("Exchanges the one-time code without placing it in the URL")
  func exchange() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"access_token":"access-1","refresh_token":"refresh-1"}"#)
    ])
    let client = MobileSSOHTTPClient(dataTransport: stub)
    let tokens = try await client.exchange(
      code: "private-code",
      server: OAuthServerURL("https://sure.example/base")
    )

    #expect(tokens.accessToken == "access-1")
    let request = try #require(await stub.requests().first)
    #expect(request.url?.absoluteString == "https://sure.example/base/api/v1/auth/sso_exchange")
    #expect(request.url?.absoluteString.contains("private-code") == false)
    #expect(request.httpMethod == "POST")
    #expect(try jsonObject(request)["code"] as? String == "private-code")
  }

  @Test("Signs in with email, password, and complete device information")
  func passwordLogin() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"access_token":"access-1","refresh_token":"refresh-1"}"#)
    ])
    let client = MobileSSOHTTPClient(dataTransport: stub)
    _ = try await client.login(
      email: "user@example.com",
      password: "Password1!",
      device: MobileDeviceInformation(
        deviceID: "device-123",
        deviceName: "Test iPhone",
        deviceType: "ios",
        osVersion: "26.5",
        appVersion: "0.7.4"
      ),
      server: OAuthServerURL("https://sure.example")
    )

    let request = try #require(await stub.requests().first)
    #expect(request.url?.absoluteString == "https://sure.example/api/v1/auth/login")
    let body = try jsonObject(request)
    #expect(body["email"] as? String == "user@example.com")
    #expect(body["password"] as? String == "Password1!")
    let device = try #require(body["device"] as? [String: Any])
    #expect(device["device_id"] as? String == "device-123")
    #expect(device["device_type"] as? String == "ios")
  }

  @Test("Recognizes a password login MFA challenge")
  func passwordLoginMFA() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"error":"Two-factor authentication required","mfa_required":true}"#, status: 401)
    ])
    let client = MobileSSOHTTPClient(dataTransport: stub)

    await #expect(throws: MobileSSOError.mfaRequired) {
      try await client.login(
        email: "user@example.com",
        password: "Password1!",
        device: MobileDeviceInformation(
          deviceID: "device-123",
          deviceName: "Test iPhone",
          deviceType: "ios",
          osVersion: "26.5",
          appVersion: "0.7.4"
        ),
        server: OAuthServerURL("https://sure.example")
      )
    }
  }

  @Test("Refreshes mobile tokens with their stable device identifier")
  func refresh() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"access_token":"access-2","refresh_token":"refresh-2"}"#)
    ])
    let client = MobileSSOHTTPClient(dataTransport: stub)
    _ = try await client.refresh(
      refreshToken: "refresh-1",
      deviceID: "device-123",
      server: OAuthServerURL("https://sure.example")
    )

    let request = try #require(await stub.requests().first)
    let body = try jsonObject(request)
    #expect(body["refresh_token"] as? String == "refresh-1")
    let device = try #require(body["device"] as? [String: Any])
    #expect(device["device_id"] as? String == "device-123")
  }

  private func queryValues(_ url: URL) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    ).compactMap { item in
      item.value.map { (item.name, $0) }
    })
  }

  @MainActor
  private func testDeviceInformationProvider() -> MobileDeviceInformationProvider {
    let suiteName = "MobileSSOTests.\(UUID().uuidString)"
    return MobileDeviceInformationProvider(
      defaults: UserDefaults(suiteName: suiteName)!,
      makeID: { UUID(uuidString: "00000000-0000-0000-0000-000000000123")! }
    )
  }

  private func jsonObject(_ request: URLRequest) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(
      with: #require(request.httpBody)
    ) as? [String: Any])
  }
}
