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
    #expect(throws: MobileSSOError.providerUnavailable) {
      try MobileSSOCallback.parse(#require(URL(
        string: "sureapp://oauth/callback?error=invalid_provider&message=private"
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

  private func jsonObject(_ request: URLRequest) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(
      with: #require(request.httpBody)
    ) as? [String: Any])
  }
}
