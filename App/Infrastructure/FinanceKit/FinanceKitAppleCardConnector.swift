#if os(iOS)
import FinanceKit

struct FinanceKitAppleCardConnector: AppleCardConnecting {
  var isAvailable: Bool {
    FinanceStore.isDataAvailable(.financialData)
  }

  func authorizationStatus() async throws -> AppleCardAuthorization {
    try await map(FinanceStore.shared.authorizationStatus())
  }

  func requestAuthorization() async throws -> AppleCardAuthorization {
    try await map(FinanceStore.shared.requestAuthorization())
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
