struct StoredPushSubscriptionState: Codable, Equatable, Sendable {
  var active: StoredPushSubscription?
  var pendingUnregistrations: [StoredPushSubscription]

  init(
    active: StoredPushSubscription? = nil,
    pendingUnregistrations: [StoredPushSubscription] = []
  ) {
    self.active = active
    self.pendingUnregistrations = pendingUnregistrations
  }
}
