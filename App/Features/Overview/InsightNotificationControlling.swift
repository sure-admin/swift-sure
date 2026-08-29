@MainActor
protocol InsightNotificationControlling {
  func enableInsightNotifications() async -> Bool
  func disableInsightNotifications() async
}
