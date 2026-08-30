import AuthenticationServices
import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class MobileSSOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
  private var httpClient: MobileSSOHTTPClient
  private var deviceInformation: MobileDeviceInformationProvider
  private var authenticationSession: ASWebAuthenticationSession?

  init(
    httpClient: MobileSSOHTTPClient,
    deviceInformation: MobileDeviceInformationProvider
  ) {
    self.httpClient = httpClient
    self.deviceInformation = deviceInformation
    super.init()
  }

  func signIn(
    provider: SSOProvider,
    serverURL: String
  ) async throws -> MobileSSOResult {
    let server = try OAuthServerURL(serverURL)
    let device = deviceInformation.information()
    let url = try Self.authorizationURL(
      server: server,
      provider: provider,
      device: device
    )
    let callbackURL = try await authenticate(at: url)
    switch try MobileSSOCallback.parse(callbackURL) {
    case .authorizationCode(let code):
      let tokens = try await httpClient.exchange(code: code, server: server)
      return .authenticated(tokens, deviceID: device.deviceID)
    case .onboarding(let context):
      return .onboarding(context)
    }
  }

  static func authorizationURL(
    server: OAuthServerURL,
    provider: SSOProvider,
    device: MobileDeviceInformation
  ) throws -> URL {
    var components = URLComponents(
      url: server.appending(path: "auth/mobile").appending(path: provider.rawValue),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
      URLQueryItem(name: "device_id", value: device.deviceID),
      URLQueryItem(name: "device_name", value: device.deviceName),
      URLQueryItem(name: "device_type", value: device.deviceType),
      URLQueryItem(name: "os_version", value: device.osVersion),
      URLQueryItem(name: "app_version", value: device.appVersion)
    ]
    guard let url = components?.url else { throw MobileSSOError.couldNotStart }
    return url
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    #if os(iOS)
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    #elseif os(macOS)
    return NSApplication.shared.keyWindow
      ?? NSApplication.shared.windows.first
      ?? ASPresentationAnchor()
    #endif
  }

  private func authenticate(at url: URL) async throws -> URL {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let session = ASWebAuthenticationSession(
          url: url,
          callbackURLScheme: "sureapp"
        ) { [weak self] callbackURL, error in
          self?.authenticationSession = nil
          if let callbackURL {
            continuation.resume(returning: callbackURL)
          } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
            continuation.resume(throwing: CancellationError())
          } else {
            continuation.resume(throwing: MobileSSOError.signInFailed)
          }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authenticationSession = session
        guard session.start() else {
          authenticationSession = nil
          continuation.resume(throwing: MobileSSOError.couldNotStart)
          return
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.authenticationSession?.cancel()
        self?.authenticationSession = nil
      }
    }
  }
}

extension MobileSSOAuthService: MobileSSOAuthenticating { }
