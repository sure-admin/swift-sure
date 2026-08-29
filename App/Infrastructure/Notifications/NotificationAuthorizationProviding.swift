@MainActor
protocol NotificationAuthorizationProviding: AnyObject {
  func status() async -> NotificationAuthorizationState
  func requestAuthorization() async throws -> Bool
  func clearBadge() async
}
