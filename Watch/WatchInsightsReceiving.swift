enum WatchInsightsReceiverEvent {
  case stateChanged(WatchInsightsSessionState)
  case snapshot(Result<WatchInsightsSnapshot, WatchInsightsSnapshotCodingError>)
}

@MainActor
protocol WatchInsightsReceiving: AnyObject {
  func activate(handler: @escaping @MainActor (WatchInsightsReceiverEvent) -> Void)
}
