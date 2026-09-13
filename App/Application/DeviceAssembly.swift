import Foundation

@MainActor
struct DeviceAssembly {
  let notifications: NotificationManager
  let syncInsights: ([BackendInsight]) -> Void
  let activate: () -> Void

  init(connection services: ConnectionAssembly) {
    let connection = services.connection
    let session = services.session
    let apiClient = services.apiClient
    let pushDeviceIdentity = PushDeviceIdentity(secrets: KeychainSecretValueStore())
    let notificationManager = NotificationManager(
      currentServerURL: {
        let context = try? await session.requestContext()
        return context?.baseURL
      },
      currentConnectionIdentity: { [weak connection] in connection?.connectedSnapshotIdentity },
      provesDeviceContinuity: true,
      pushSubscriptions: PushSubscriptionOperations(
        register: { token, environment in
          let context = try await session.requestContext()
          let key = try pushDeviceIdentity.key(for: context.baseURL)
          return try await apiClient.registerPushSubscription(
            token: token,
            environment: environment,
            deviceKey: key
          )
        },
        unregister: { identifier in
          try await apiClient.unregisterPushSubscription(id: identifier)
        }
      ),
      authorization: SystemNotificationAuthorizationProvider(),
      remoteRegistration: SystemRemoteNotificationRegistrar(),
      storage: LiveNotificationStateStore(),
      environment: { .current }
    )
    #if os(iOS)
    let watchSequence = WatchSnapshotSequence(defaults: .standard)
    let watchInsightsSync = WatchInsightsSync(
      transport: WatchConnectivityInsightsSender(),
      now: { .now },
      nextRevision: { watchSequence.next() }
    )
    let syncInsights: ([BackendInsight]) -> Void = { insights in
      watchInsightsSync.send(insights)
    }
    #else
    let syncInsights: ([BackendInsight]) -> Void = { _ in }
    #endif
    notifications = notificationManager
    self.syncInsights = syncInsights
    #if os(iOS)
    activate = { watchInsightsSync.activate() }
    #else
    activate = {}
    #endif
  }
}
