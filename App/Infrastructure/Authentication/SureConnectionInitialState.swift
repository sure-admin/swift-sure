import Foundation

struct SureConnectionInitialState {
  static let defaultServerURL = "https://demo.sure.am"

  var serverURL: String
  var credentials: StoredCredentialSnapshot
  var isExplicitlySignedOut: Bool
  var requestContext: SureRequestContext?
  var initializationError: String?

  static func load(
    credentials repository: any CredentialRepository,
    preferences: any ConnectionPreferences,
    defaultServerURL: String = SureConnectionInitialState.defaultServerURL
  ) -> SureConnectionInitialState {
    let savedServerURL = preferences.serverURL() ?? defaultServerURL
    let isSignedOut = preferences.isExplicitlySignedOut()

    let credentials: StoredCredentialSnapshot
    do {
      credentials = try repository.loadCredentials()
    } catch let error as CredentialRepositoryError {
      return failedState(serverURL: savedServerURL, isSignedOut: isSignedOut, error: error)
    } catch {
      return failedState(
        serverURL: savedServerURL,
        isSignedOut: isSignedOut,
        error: CredentialRepositoryError.invalidStoredCredentials
      )
    }

    do {
      let storedContext: SureRequestContext?
      if let oauth = credentials.oauthSession, oauth.isVerified {
        storedContext = try SureRequestContext(
          baseURL: oauth.serverURL,
          authorization: .bearer(oauth.credentials.accessToken)
        )
      } else if let apiKey = credentials.apiKeySession, apiKey.isVerified {
        storedContext = try SureRequestContext(
          baseURL: apiKey.serverURL,
          authorization: .apiKey(apiKey.apiKey)
        )
      } else {
        storedContext = nil
      }
      let context = isSignedOut ? nil : storedContext
      let displayServerURL = context?.baseURL.absoluteString ?? savedServerURL

      return SureConnectionInitialState(
        serverURL: displayServerURL,
        credentials: credentials,
        isExplicitlySignedOut: isSignedOut,
        requestContext: context,
        initializationError: nil
      )
    } catch {
      return SureConnectionInitialState(
        serverURL: savedServerURL,
        credentials: credentials,
        isExplicitlySignedOut: isSignedOut,
        requestContext: nil,
        initializationError: SureRequestContextError.invalidBaseURL.localizedDescription
      )
    }
  }

  private static func failedState(
    serverURL: String,
    isSignedOut: Bool,
    error: any LocalizedError
  ) -> SureConnectionInitialState {
    SureConnectionInitialState(
      serverURL: serverURL,
      credentials: StoredCredentialSnapshot(session: nil),
      isExplicitlySignedOut: isSignedOut,
      requestContext: nil,
      initializationError: error.errorDescription ?? "The saved Sure connection couldn’t be loaded."
    )
  }
}
