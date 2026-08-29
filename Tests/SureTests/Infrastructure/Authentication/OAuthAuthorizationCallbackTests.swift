import Foundation
import Testing
@testable import Sure

@Suite("OAuth authorization callback")
struct OAuthAuthorizationCallbackTests {
  @Test("Parses one matching state and authorization code")
  func success() throws {
    let url = try #require(URL(
      string: "http://127.0.0.1:53921/oauth/callback?state=expected&code=code-123"
    ))

    let callback = try OAuthAuthorizationCallback.parse(url, expectedState: "expected")

    #expect(callback.code == "code-123")
  }

  @Test("Maps provider details to a non-echoing authorization error")
  func providerError() throws {
    let url = try #require(URL(
      string: "http://127.0.0.1:53921/oauth/callback?error=access_denied&error_description=Sign-in%20cancelled"
    ))

    do {
      _ = try OAuthAuthorizationCallback.parse(url, expectedState: "expected")
      #expect(Bool(false))
    } catch let error as PasskeyOAuthError {
      #expect(error == .authorizationRejected)
      #expect(!error.localizedDescription.contains("Sign-in cancelled"))
    }
  }

  @Test("Rejects duplicate state, code, and error parameters")
  func duplicateProtectedParameters() throws {
    let values = [
      "state=expected&state=other&code=code-123",
      "state=expected&code=code-123&code=code-456",
      "error=access_denied&error=invalid_request"
    ]

    for value in values {
      let url = try #require(URL(
        string: "http://127.0.0.1:53921/oauth/callback?\(value)"
      ))
      do {
        _ = try OAuthAuthorizationCallback.parse(url, expectedState: "expected")
        #expect(Bool(false))
      } catch let error as PasskeyOAuthError {
        #expect(error == .invalidResponse)
      }
    }
  }

  @Test("Rejects mismatched state and contradictory success and error values")
  func invalidCallback() throws {
    let values = [
      "state=other&code=code-123",
      "state=expected&code=code-123&error=access_denied"
    ]

    for value in values {
      let url = try #require(URL(
        string: "http://127.0.0.1:53921/oauth/callback?\(value)"
      ))
      do {
        _ = try OAuthAuthorizationCallback.parse(url, expectedState: "expected")
        #expect(Bool(false))
      } catch let error as PasskeyOAuthError {
        #expect(error == .invalidResponse)
      }
    }
  }
}
