#if os(iOS)
import FinanceKit

struct FinanceKitAppleCardConnector: AppleCardConnecting {
  var isAvailable: Bool {
    #if targetEnvironment(simulator)
    false
    #else
    FinanceStore.isDataAvailable(.financialData)
    #endif
  }

  func authorizationStatus() async throws -> AppleCardAuthorization {
    #if targetEnvironment(simulator)
    return .denied
    #else
    return try await map(FinanceStore.shared.authorizationStatus())
    #endif
  }

  func requestAuthorization() async throws -> AppleCardAuthorization {
    #if targetEnvironment(simulator)
    return .denied
    #else
    return try await map(FinanceStore.shared.requestAuthorization())
    #endif
  }

  private func map(_ status: AuthorizationStatus) -> AppleCardAuthorization {
    switch status {
    case .notDetermined: .notDetermined
    case .authorized: .authorized
    case .denied: .denied
    @unknown default: .denied
    }
  }
}
#else
struct FinanceKitAppleCardConnector: AppleCardConnecting {
  var isAvailable: Bool { false }

  func authorizationStatus() async throws -> AppleCardAuthorization { .denied }
  func requestAuthorization() async throws -> AppleCardAuthorization { .denied }
}
#endif
