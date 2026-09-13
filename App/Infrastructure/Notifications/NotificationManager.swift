import Foundation

@MainActor
final class NotificationManager {
  private let provesDeviceContinuity: Bool
  private var currentConnectionIdentity: () -> String?
  private var currentServerURL: () async -> URL?
  private var pushSubscriptions: PushSubscriptionOperations
  private var authorization: any NotificationAuthorizationProviding
  private var remoteRegistration: any RemoteNotificationRegistering
  private var storage: any NotificationStateStoring
  private var environment: () -> APNsEnvironment
  private var registrationTask: Task<Void, Never>?
  private var isRegistrationBlocked = false

  init(
    currentServerURL: @escaping () async -> URL?,
    currentConnectionIdentity: @escaping () -> String? = { nil },
    provesDeviceContinuity: Bool = false,
    pushSubscriptions: PushSubscriptionOperations,
    authorization: any NotificationAuthorizationProviding,
    remoteRegistration: any RemoteNotificationRegistering,
    storage: any NotificationStateStoring,
    environment: @escaping () -> APNsEnvironment
  ) {
    self.provesDeviceContinuity = provesDeviceContinuity
    self.currentConnectionIdentity = currentConnectionIdentity
    self.currentServerURL = currentServerURL
    self.pushSubscriptions = pushSubscriptions
    self.authorization = authorization
    self.remoteRegistration = remoteRegistration
    self.storage = storage
    self.environment = environment
  }

  func enableInsightNotifications() async -> Bool {
    do {
      let isAuthorized = switch await authorization.status() {
      case .authorized:
        true
      case .notDetermined:
        try await authorization.requestAuthorization()
      case .denied:
        false
      }

      guard isAuthorized else {
        storage.insightNotificationsEnabled = false
        return false
      }
      storage.insightNotificationsEnabled = true
      remoteRegistration.registerForRemoteNotifications()
      await registerStoredDeviceTokenIfNeeded()
      return true
    } catch {
      storage.insightNotificationsEnabled = false
      record(error)
      return false
    }
  }

  func disableInsightNotifications() async {
    storage.insightNotificationsEnabled = false
    await awaitInFlightRegistration()

    guard let serverURL = await normalizedCurrentServerURL() else {
      detachActiveSubscriptionForLaterCleanup()
      return
    }
    migrateLegacySubscription(for: serverURL)
    await retryPendingUnregistrations(on: serverURL)
    await cleanActiveSubscription(on: serverURL)
  }

  func registerStoredDeviceTokenIfNeeded() async {
    guard !isRegistrationBlocked else { return }

    if let registrationTask {
      await registrationTask.value
      return
    }

    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await performStoredDeviceTokenRegistration()
    }
    registrationTask = task
    await task.value
    registrationTask = nil
  }

  private func performStoredDeviceTokenRegistration() async {
    guard let serverURL = await normalizedCurrentServerURL() else { return }
    migrateLegacySubscription(for: serverURL)

    guard !isRegistrationBlocked,
          storage.insightNotificationsEnabled,
          let token = storage.deviceToken,
          !token.isEmpty else { return }

    let connectionIdentity = currentConnectionIdentity()
    let registrationEnvironment = environment()
    guard let currentState = loadSubscriptionState() else { return }
    if let active = currentState.active {
      if active.serverURL == serverURL,
         active.connectionIdentity == connectionIdentity,
         active.deviceToken == token,
         active.environment == registrationEnvironment {
        return
      }

      if active.serverURL == serverURL {
        await cleanActiveSubscription(on: serverURL)
      } else {
        detachActiveSubscriptionForLaterCleanup()
      }
    }

    guard !isRegistrationBlocked else { return }

    do {
      let identifier = try await pushSubscriptions.register(token, registrationEnvironment)
      let subscription = try StoredPushSubscription(
        id: identifier,
        serverURL: serverURL,
        deviceToken: token,
        environment: registrationEnvironment,
        connectionIdentity: connectionIdentity
      )
      do {
        var state = try storage.loadSubscriptionState()
        if let displaced = state.active, displaced != subscription {
          enqueue(displaced, in: &state)
        }
        state.active = subscription
        // Successful registration with this installation's proof supersedes the
        // old row. Backend transfers create a fresh ID, so delayed deletes are safe.
        if provesDeviceContinuity && connectionIdentity != nil {
          state.pendingUnregistrations.removeAll {
            $0.serverURL == serverURL && $0.deviceToken == token
          }
        }
        try storage.saveSubscriptionState(state)
        storage.registrationError = nil
      } catch {
        record(error)
        await compensateForUnstoredRegistration(subscription, on: serverURL)
      }
    } catch {
      record(error)
    }
  }

  private func awaitInFlightRegistration() async {
    guard let registrationTask else { return }
    await registrationTask.value
    self.registrationTask = nil
  }

  private func normalizedCurrentServerURL() async -> URL? {
    guard let serverURL = await currentServerURL() else { return nil }
    return try? SureRequestContext(baseURL: serverURL, authorization: nil).baseURL
  }

  private func migrateLegacySubscription(for serverURL: URL) {
    guard let identifier = storage.legacySubscriptionID,
          let token = storage.deviceToken,
          !token.isEmpty,
          let subscription = try? StoredPushSubscription(
            id: identifier,
            serverURL: serverURL,
            deviceToken: token,
            environment: environment()
          ) else { return }

    guard var state = loadSubscriptionState() else { return }
    if state.active?.id != identifier || state.active?.serverURL != serverURL {
      enqueue(subscription, in: &state)
      guard saveSubscriptionState(state) else { return }
    }
    storage.legacySubscriptionID = nil
  }

  private func cleanActiveSubscription(on serverURL: URL) async {
    guard let active = loadSubscriptionState()?.active else { return }
    guard active.serverURL == serverURL, active.connectionIdentity == currentConnectionIdentity() else {
      detachActiveSubscriptionForLaterCleanup()
      return
    }

    let wasRemoved = await unregister(active, on: serverURL)
    guard var state = loadSubscriptionState() else { return }
    guard state.active == active else { return }
    state.active = nil
    if !wasRemoved {
      enqueue(active, in: &state)
    }
    guard saveSubscriptionState(state) else { return }
    if wasRemoved,
       !state.pendingUnregistrations.contains(where: { $0.serverURL == serverURL }) {
      storage.registrationError = nil
    }
  }

  private func detachActiveSubscriptionForLaterCleanup() {
    guard var state = loadSubscriptionState() else { return }
    guard let active = state.active else { return }
    state.active = nil
    enqueue(active, in: &state)
    saveSubscriptionState(state)
  }

  private func retryPendingUnregistrations(on serverURL: URL) async {
    guard let state = loadSubscriptionState() else { return }
    let targets = state.pendingUnregistrations.filter {
      $0.serverURL == serverURL && $0.connectionIdentity == currentConnectionIdentity()
    }
    guard !targets.isEmpty else { return }

    var encounteredFailure = false
    for target in targets {
      if await unregister(target, on: serverURL) {
        guard var state = loadSubscriptionState() else {
          encounteredFailure = true
          continue
        }
        state.pendingUnregistrations.removeAll { $0 == target }
        if !saveSubscriptionState(state) {
          encounteredFailure = true
        }
      } else {
        encounteredFailure = true
      }
    }
    if !encounteredFailure {
      storage.registrationError = nil
    }
  }

  private func unregister(_ subscription: StoredPushSubscription, on serverURL: URL) async -> Bool {
    guard subscription.serverURL == serverURL,
          subscription.connectionIdentity == currentConnectionIdentity() else { return false }

    do {
      try await pushSubscriptions.unregister(subscription.id)
      return true
    } catch SureAPIError.notFound {
      return true
    } catch {
      record(error)
      return false
    }
  }

  private func compensateForUnstoredRegistration(
    _ subscription: StoredPushSubscription,
    on serverURL: URL
  ) async {
    guard await unregister(subscription, on: serverURL) == false else { return }
    guard var state = loadSubscriptionState() else { return }
    enqueue(subscription, in: &state)
    saveSubscriptionState(state)
  }

  private func loadSubscriptionState() -> StoredPushSubscriptionState? {
    do {
      return try storage.loadSubscriptionState()
    } catch {
      record(error)
      return nil
    }
  }

  @discardableResult
  private func saveSubscriptionState(_ state: StoredPushSubscriptionState) -> Bool {
    do {
      try storage.saveSubscriptionState(state)
      return true
    } catch {
      record(error)
      return false
    }
  }

  private func enqueue(
    _ subscription: StoredPushSubscription,
    in state: inout StoredPushSubscriptionState
  ) {
    guard !state.pendingUnregistrations.contains(subscription) else { return }
    state.pendingUnregistrations.append(subscription)
  }

  private func record(_ error: Error) {
    storage.registrationError = error.localizedDescription
  }
}

extension NotificationManager: InsightNotificationControlling { }

extension NotificationManager: AuthenticationNotificationLifecycle {
  func didConnect() async {
    guard let serverURL = await normalizedCurrentServerURL() else { return }
    migrateLegacySubscription(for: serverURL)
    await retryPendingUnregistrations(on: serverURL)
    isRegistrationBlocked = false
    await registerStoredDeviceTokenIfNeeded()
  }

  func prepareForConnectionChange() async {
    isRegistrationBlocked = true
    await awaitInFlightRegistration()

    guard let serverURL = await normalizedCurrentServerURL() else {
      detachActiveSubscriptionForLaterCleanup()
      return
    }
    migrateLegacySubscription(for: serverURL)
    await retryPendingUnregistrations(on: serverURL)
    await cleanActiveSubscription(on: serverURL)
  }

  func prepareForLogout() async {
    storage.insightNotificationsEnabled = false
    await prepareForConnectionChange()
  }
}

extension NotificationManager: RemoteNotificationEventHandling {
  func applicationDidFinishLaunching() async {
    guard await authorization.status() == .authorized else { return }
    remoteRegistration.registerForRemoteNotifications()
    await registerStoredDeviceTokenIfNeeded()
  }

  func receiveDeviceToken(_ token: String) async {
    storage.deviceToken = token
    await registerStoredDeviceTokenIfNeeded()
  }

  func receiveRemoteRegistrationFailure(_ error: Error) {
    record(error)
  }

  func receiveNotificationResponse(insightID: String?) async {
    if let insightID {
      storage.pendingInsightID = insightID
    }
    await authorization.clearBadge()
  }
}
