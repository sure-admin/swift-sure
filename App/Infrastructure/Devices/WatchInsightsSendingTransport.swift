#if os(iOS)
@MainActor
protocol WatchInsightsSendingTransport: AnyObject {
  var sessionState: WatchInsightsSessionState { get }

  func activate(
    stateDidChange: @escaping @MainActor (WatchInsightsSessionState) -> Void
  )
  func updateApplicationContext(_ applicationContext: [String: Any]) throws
}
#endif
