import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class MobileSSOAuthService {
  private var httpClient: MobileSSOHTTPClient
  private var deviceInformation: MobileDeviceInformationProvider
  private var openURL: @MainActor (URL) async -> Bool
  private var callbackContinuation: CheckedContinuation<URL, Error>?

  init(
    httpClient: MobileSSOHTTPClient,
    deviceInformation: MobileDeviceInformationProvider,
    openURL: @escaping @MainActor (URL) async -> Bool = MobileSSOAuthService.openSystemURL
  ) {
    self.httpClient = httpClient
    self.deviceInformation = deviceInformation
    self.openURL = openURL
  }

  func signIn(
    email: String,
    password: String,
    serverURL: String
  ) async throws -> MobileSSOResult {
    let server = try OAuthServerURL(serverURL)
    let device = deviceInformation.information()
    let tokens = try await httpClient.login(
      email: email,
      password: password,
      device: device,
      server: server
    )
    return .authenticated(tokens, deviceID: device.deviceID)
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

  func handleOpenURL(_ url: URL) {
    guard url.scheme == "sureapp",
          url.host == "oauth",
          url.path == "/callback" else { return }
    finishAuthentication(with: .success(url))
  }

  private func authenticate(at url: URL) async throws -> URL {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard callbackContinuation == nil else {
          continuation.resume(throwing: MobileSSOError.couldNotStart)
          return
        }
        callbackContinuation = continuation
        Task { @MainActor in
          guard await openURL(url) else {
            finishAuthentication(with: .failure(MobileSSOError.couldNotStart))
            return
          }
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.finishAuthentication(with: .failure(CancellationError()))
      }
    }
  }

  private func finishAuthentication(with result: Result<URL, Error>) {
    let continuation = callbackContinuation
    callbackContinuation = nil
    continuation?.resume(with: result)
  }

  private static func openSystemURL(_ url: URL) async -> Bool {
    #if os(iOS)
    await withCheckedContinuation { continuation in
      UIApplication.shared.open(url, options: [:]) { opened in
        continuation.resume(returning: opened)
      }
    }
    #elseif os(macOS)
    NSWorkspace.shared.open(url)
    #endif
  }
}

extension MobileSSOAuthService: MobileSSOAuthenticating { }
