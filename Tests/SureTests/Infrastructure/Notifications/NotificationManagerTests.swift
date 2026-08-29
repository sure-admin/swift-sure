import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Notification manager")
struct NotificationManagerTests {
  @Test("An authorized notification flow stores a server-bound subscription")
  func enableWhenAuthorized() async throws {
    let authorization = NotificationAuthorizationFake(status: .authorized)
    let remoteRegistration = RemoteNotificationRegistrationSpy()
    let storage = NotificationStateFake(
      insightNotificationsEnabled: false,
      deviceToken: "00ff10",
      registrationError: "Earlier failure"
    )
    let push = PushSubscriptionSpy()
    let manager = makeManager(
      serverURL: URL(string: "https://SURE.EXAMPLE:443/")!,
      authorization: authorization,
      remoteRegistration: remoteRegistration,
      storage: storage,
      push: push
    )

    #expect(await manager.enableInsightNotifications())
    #expect(authorization.requestCount == 0)
    #expect(remoteRegistration.registrationCount == 1)
    #expect(push.registrations == [Registration(token: "00ff10", environment: .sandbox)])
    let active = try #require(storage.subscriptionState.active)
    #expect(active.id == PushSubscriptionSpy.subscriptionID)
    #expect(active.serverURL == URL(string: "https://sure.example")!)
    #expect(active.deviceToken == "00ff10")
    #expect(active.environment == .sandbox)
    #expect(storage.insightNotificationsEnabled)
    #expect(storage.registrationError == nil)
  }

  @Test("Permission is requested only when authorization is undetermined")
  func enableRequestsPermission() async {
    let authorization = NotificationAuthorizationFake(
      status: .notDetermined,
      requestResult: true
    )
    let remoteRegistration = RemoteNotificationRegistrationSpy()
    let manager = makeManager(
      authorization: authorization,
      remoteRegistration: remoteRegistration
    )

    #expect(await manager.enableInsightNotifications())
    #expect(authorization.requestCount == 1)
    #expect(remoteRegistration.registrationCount == 1)
  }

  @Test("Denied permission disables the preference without registering")
  func deniedPermission() async {
    let authorization = NotificationAuthorizationFake(status: .denied)
    let remoteRegistration = RemoteNotificationRegistrationSpy()
    let storage = NotificationStateFake(insightNotificationsEnabled: true)
    let push = PushSubscriptionSpy()
    let manager = makeManager(
      authorization: authorization,
      remoteRegistration: remoteRegistration,
      storage: storage,
      push: push
    )

    #expect(await manager.enableInsightNotifications() == false)
    #expect(authorization.requestCount == 0)
    #expect(remoteRegistration.registrationCount == 0)
    #expect(push.registrations.isEmpty)
    #expect(storage.insightNotificationsEnabled == false)
  }

  @Test("Launch re-registers with APNs only when permission was already granted")
  func launchRegistration() async {
    let authorized = NotificationAuthorizationFake(status: .authorized)
    let authorizedRegistrar = RemoteNotificationRegistrationSpy()
    let authorizedManager = makeManager(
      authorization: authorized,
      remoteRegistration: authorizedRegistrar
    )
    await authorizedManager.applicationDidFinishLaunching()

    let undetermined = NotificationAuthorizationFake(status: .notDetermined)
    let undeterminedRegistrar = RemoteNotificationRegistrationSpy()
    let undeterminedManager = makeManager(
      authorization: undetermined,
      remoteRegistration: undeterminedRegistrar
    )
    await undeterminedManager.applicationDidFinishLaunching()

    #expect(authorizedRegistrar.registrationCount == 1)
    #expect(authorized.requestCount == 0)
    #expect(undeterminedRegistrar.registrationCount == 0)
    #expect(undetermined.requestCount == 0)
  }

  @Test("Registration requires an authenticated server, preference, and token")
  func registrationPrerequisites() async {
    let cases = [
      PrerequisiteCase(enabled: false, serverURL: serverA, token: "token"),
      PrerequisiteCase(enabled: true, serverURL: nil, token: "token"),
      PrerequisiteCase(enabled: true, serverURL: serverA, token: nil)
    ]

    for prerequisite in cases {
      let storage = NotificationStateFake(
        insightNotificationsEnabled: prerequisite.enabled,
        deviceToken: prerequisite.token
      )
      let push = PushSubscriptionSpy()
      let manager = makeManager(
        serverURL: prerequisite.serverURL,
        storage: storage,
        push: push
      )

      await manager.registerStoredDeviceTokenIfNeeded()

      #expect(push.registrations.isEmpty)
      #expect(storage.subscriptionState.active == nil)
    }
  }

  @Test("An unchanged active subscription is not registered twice")
  func activeRegistrationReuse() async throws {
    let active = try subscription(serverURL: serverA)
    let storage = NotificationStateFake(
      insightNotificationsEnabled: true,
      deviceToken: active.deviceToken,
      subscriptionState: StoredPushSubscriptionState(active: active)
    )
    let push = PushSubscriptionSpy()
    let manager = makeManager(storage: storage, push: push)

    await manager.didConnect()

    #expect(push.registrations.isEmpty)
    #expect(push.unregistrations.isEmpty)
    #expect(storage.subscriptionState.active == active)
  }

  @Test("A failed subscription save unregisters the newly created server record")
  func registrationSaveFailureCompensation() async {
    let storage = NotificationStateFake(
      insightNotificationsEnabled: true,
      deviceToken: "device-token",
      saveFailuresRemaining: 1
    )
    let push = PushSubscriptionSpy()
    let manager = makeManager(storage: storage, push: push)

    await manager.registerStoredDeviceTokenIfNeeded()

    #expect(push.registrations.count == 1)
    #expect(push.unregistrations == [PushSubscriptionSpy.subscriptionID])
    #expect(storage.subscriptionState.active == nil)
    #expect(storage.subscriptionState.pendingUnregistrations.isEmpty)
    #expect(
      storage.registrationError
        == NotificationStateStoreError.persistenceFailed.localizedDescription
    )
  }

  @Test("A failed compensating unregister is retained for a later host-safe retry")
  func registrationSaveAndCompensationFailure() async throws {
    let storage = NotificationStateFake(
      insightNotificationsEnabled: true,
      deviceToken: "device-token",
      saveFailuresRemaining: 1
    )
    let push = PushSubscriptionSpy(unregisterError: NotificationTestError.expected)
    let manager = makeManager(storage: storage, push: push)

    await manager.registerStoredDeviceTokenIfNeeded()

    let pending = try #require(storage.subscriptionState.pendingUnregistrations.first)
    #expect(push.registrations.count == 1)
    #expect(push.unregistrations == [PushSubscriptionSpy.subscriptionID])
    #expect(pending.id == PushSubscriptionSpy.subscriptionID)
    #expect(pending.serverURL == serverA)
    #expect(pending.deviceToken == "device-token")
    #expect(pending.environment == .sandbox)
    #expect(storage.registrationError == "Expected failure")
  }

  @Test("A subscription from another host is queued and never unregistered on the new host")
  func crossHostIsolation() async throws {
    let oldSubscription = try subscription(serverURL: serverA)
    let storage = NotificationStateFake(
      insightNotificationsEnabled: true,
      deviceToken: "new-token",
      subscriptionState: StoredPushSubscriptionState(active: oldSubscription)
    )
    let push = PushSubscriptionSpy()
    let manager = makeManager(serverURL: serverB, storage: storage, push: push)

    await manager.didConnect()

    #expect(push.unregistrations.isEmpty)
    #expect(storage.subscriptionState.pendingUnregistrations == [oldSubscription])
    #expect(storage.subscriptionState.active?.serverURL == serverB)
    #expect(storage.subscriptionState.active?.deviceToken == "new-token")
  }

  @Test("Connection changes remove a matching active subscription and preserve preference")
  func connectionChangeCleanup() async throws {
    let active = try subscription(serverURL: serverA)
    let storage = NotificationStateFake(
      insightNotificationsEnabled: true,
      deviceToken: active.deviceToken,
      subscriptionState: StoredPushSubscriptionState(active: active)
    )
    let push = PushSubscriptionSpy()
    let manager = makeManager(storage: storage, push: push)

    await manager.prepareForConnectionChange()
    await manager.receiveDeviceToken("replacement-token")

    #expect(push.unregistrations == [active.id])
    #expect(push.registrations.isEmpty)
    #expect(storage.subscriptionState.active == nil)
    #expect(storage.insightNotificationsEnabled)
  }

  @Test("Logout disables preference and queues a failed cleanup")
  func logoutFailureQueue() async throws {
    let active = try subscription(serverURL: serverA)
    let storage = NotificationStateFake(
      insightNotificationsEnabled: true,
      subscriptionState: StoredPushSubscriptionState(active: active)
    )
    let push = PushSubscriptionSpy(unregisterError: NotificationTestError.expected)
    let manager = makeManager(storage: storage, push: push)

    await manager.prepareForLogout()

    #expect(push.unregistrations == [active.id])
    #expect(storage.insightNotificationsEnabled == false)
    #expect(storage.subscriptionState.active == nil)
    #expect(storage.subscriptionState.pendingUnregistrations == [active])
    #expect(storage.registrationError == "Expected failure")
  }

  @Test("A failed cleanup is retried only after reconnecting to its host")
  func failedCleanupRetry() async throws {
    let active = try subscription(serverURL: serverA)
    let storage = NotificationStateFake(
      insightNotificationsEnabled: false,
      subscriptionState: StoredPushSubscriptionState(active: active)
    )
    let push = PushSubscriptionSpy(unregisterError: NotificationTestError.expected)
    let manager = makeManager(storage: storage, push: push)

    await manager.prepareForConnectionChange()
    push.unregisterError = nil
    await manager.didConnect()

    #expect(push.unregistrations == [active.id, active.id])
    #expect(storage.subscriptionState.pendingUnregistrations.isEmpty)
    #expect(storage.registrationError == nil)
  }

  @Test("Pending cleanup for another host waits until that host reconnects")
  func pendingCrossHostCleanup() async throws {
    let pending = try subscription(serverURL: serverA)
    let server = ServerURLBox(serverB)
    let storage = NotificationStateFake(
      subscriptionState: StoredPushSubscriptionState(pendingUnregistrations: [pending])
    )
    let push = PushSubscriptionSpy()
    let manager = makeManager(server: server, storage: storage, push: push)

    await manager.didConnect()
    #expect(push.unregistrations.isEmpty)
    #expect(storage.subscriptionState.pendingUnregistrations == [pending])

    server.url = serverA
    await manager.didConnect()
    #expect(push.unregistrations == [pending.id])
    #expect(storage.subscriptionState.pendingUnregistrations.isEmpty)
  }

  @Test("A missing server subscription counts as successful cleanup")
  func notFoundCleanup() async throws {
    let active = try subscription(serverURL: serverA)
    let storage = NotificationStateFake(
      subscriptionState: StoredPushSubscriptionState(active: active)
    )
    let push = PushSubscriptionSpy(unregisterError: SureAPIError.notFound)
    let manager = makeManager(storage: storage, push: push)

    await manager.prepareForConnectionChange()

    #expect(push.unregistrations == [active.id])
    #expect(storage.subscriptionState.active == nil)
    #expect(storage.subscriptionState.pendingUnregistrations.isEmpty)
    #expect(storage.registrationError == nil)
  }

  @Test("A connection transition waits for registration then cleans its result")
  func inFlightRegistrationTransition() async {
    let storage = NotificationStateFake(
      insightNotificationsEnabled: true,
      deviceToken: "device-token"
    )
    let gate = SuspendedRegistration()
    let transitionStarted = MainActorSignal()
    let push = PushSubscriptionSpy()
    let manager = NotificationManager(
      currentServerURL: { serverA },
      pushSubscriptions: PushSubscriptionOperations(
        register: { token, environment in
          await gate.register(token: token, environment: environment)
        },
        unregister: { identifier in
          push.unregistrations.append(identifier)
        }
      ),
      authorization: NotificationAuthorizationFake(status: .authorized),
      remoteRegistration: RemoteNotificationRegistrationSpy(),
      storage: storage,
      environment: { .sandbox }
    )

    let registration = Task { await manager.registerStoredDeviceTokenIfNeeded() }
    await gate.waitUntilStarted()
    let transition = Task {
      transitionStarted.signal()
      await manager.prepareForConnectionChange()
    }
    await transitionStarted.wait()
    await manager.receiveDeviceToken("replacement-token")

    #expect(gate.callCount == 1)
    gate.complete(with: PushSubscriptionSpy.subscriptionID)
    await registration.value
    await transition.value

    #expect(gate.callCount == 1)
    #expect(push.unregistrations == [PushSubscriptionSpy.subscriptionID])
    #expect(storage.subscriptionState.active == nil)
    #expect(storage.subscriptionState.pendingUnregistrations.isEmpty)
  }

  @Test("A legacy identifier is bound to the authenticated host and queued for cleanup")
  func legacyMigration() async throws {
    let legacyID = UUID(uuidString: "00000000-0000-4000-8000-000000000899")!
    let storage = NotificationStateFake(
      deviceToken: "legacy-token",
      legacySubscriptionID: legacyID
    )
    let push = PushSubscriptionSpy(unregisterError: NotificationTestError.expected)
    let manager = makeManager(
      serverURL: URL(string: "https://SURE-A.EXAMPLE:443/")!,
      storage: storage,
      push: push
    )

    await manager.didConnect()

    let pending = try #require(storage.subscriptionState.pendingUnregistrations.first)
    #expect(pending.id == legacyID)
    #expect(pending.serverURL == serverA)
    #expect(pending.deviceToken == "legacy-token")
    #expect(pending.environment == .sandbox)
    #expect(storage.legacySubscriptionID == nil)
    #expect(push.unregistrations == [legacyID])
  }

  @Test("Logout immediately cleans a legacy identifier on the authenticated host")
  func legacyLogoutCleanup() async {
    let legacyID = UUID(uuidString: "00000000-0000-4000-8000-000000000898")!
    let storage = NotificationStateFake(
      insightNotificationsEnabled: true,
      deviceToken: "legacy-token",
      legacySubscriptionID: legacyID
    )
    let push = PushSubscriptionSpy()
    let manager = makeManager(storage: storage, push: push)

    await manager.prepareForLogout()

    #expect(push.unregistrations == [legacyID])
    #expect(storage.subscriptionState.pendingUnregistrations.isEmpty)
    #expect(storage.legacySubscriptionID == nil)
    #expect(storage.insightNotificationsEnabled == false)
  }

  @Test("Notification responses persist navigation state and clear the badge")
  func notificationResponse() async {
    let authorization = NotificationAuthorizationFake(status: .authorized)
    let storage = NotificationStateFake()
    let manager = makeManager(authorization: authorization, storage: storage)

    await manager.receiveNotificationResponse(insightID: "insight-1")

    #expect(storage.pendingInsightID == "insight-1")
    #expect(authorization.clearBadgeCount == 1)
  }

  @Test("APNs tokens use lowercase two-character hexadecimal bytes")
  func deviceTokenFormatting() {
    #expect(APNsDeviceTokenFormatter.string(from: Data()) == "")
    #expect(
      APNsDeviceTokenFormatter.string(from: Data([0x00, 0x01, 0x0f, 0x10, 0xab, 0xff]))
        == "00010f10abff"
    )
  }

  private func makeManager(
    serverURL: URL? = URL(string: "https://sure-a.example")!,
    authorization: NotificationAuthorizationFake? = nil,
    remoteRegistration: RemoteNotificationRegistrationSpy? = nil,
    storage: NotificationStateFake? = nil,
    push: PushSubscriptionSpy? = nil
  ) -> NotificationManager {
    makeManager(
      server: ServerURLBox(serverURL),
      authorization: authorization,
      remoteRegistration: remoteRegistration,
      storage: storage,
      push: push
    )
  }

  private func makeManager(
    server: ServerURLBox,
    authorization: NotificationAuthorizationFake? = nil,
    remoteRegistration: RemoteNotificationRegistrationSpy? = nil,
    storage: NotificationStateFake? = nil,
    push: PushSubscriptionSpy? = nil
  ) -> NotificationManager {
    let authorization = authorization ?? NotificationAuthorizationFake(status: .authorized)
    let remoteRegistration = remoteRegistration ?? RemoteNotificationRegistrationSpy()
    let storage = storage ?? NotificationStateFake(
      insightNotificationsEnabled: true,
      deviceToken: "device-token"
    )
    let push = push ?? PushSubscriptionSpy()

    return NotificationManager(
      currentServerURL: { server.url },
      pushSubscriptions: push.operations,
      authorization: authorization,
      remoteRegistration: remoteRegistration,
      storage: storage,
      environment: { .sandbox }
    )
  }

  private func subscription(
    id: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000801")!,
    serverURL: URL,
    token: String = "device-token",
    environment: APNsEnvironment = .sandbox
  ) throws -> StoredPushSubscription {
    try StoredPushSubscription(
      id: id,
      serverURL: serverURL,
      deviceToken: token,
      environment: environment
    )
  }

  private var serverA: URL { URL(string: "https://sure-a.example")! }
  private var serverB: URL { URL(string: "https://sure-b.example")! }
}

private struct PrerequisiteCase {
  var enabled: Bool
  var serverURL: URL?
  var token: String?
}

private struct Registration: Equatable {
  var token: String
  var environment: APNsEnvironment
}

private enum NotificationTestError: LocalizedError {
  case expected

  var errorDescription: String? { "Expected failure" }
}

@MainActor
private final class ServerURLBox {
  var url: URL?

  init(_ url: URL?) {
    self.url = url
  }
}

@MainActor
private final class NotificationAuthorizationFake: NotificationAuthorizationProviding {
  var authorizationStatus: NotificationAuthorizationState
  var requestResult: Bool
  var requestError: NotificationTestError?
  private(set) var requestCount = 0
  private(set) var clearBadgeCount = 0

  init(
    status: NotificationAuthorizationState,
    requestResult: Bool = false,
    requestError: NotificationTestError? = nil
  ) {
    authorizationStatus = status
    self.requestResult = requestResult
    self.requestError = requestError
  }

  func status() async -> NotificationAuthorizationState {
    authorizationStatus
  }

  func requestAuthorization() async throws -> Bool {
    requestCount += 1
    if let requestError { throw requestError }
    return requestResult
  }

  func clearBadge() async {
    clearBadgeCount += 1
  }
}

@MainActor
private final class RemoteNotificationRegistrationSpy: RemoteNotificationRegistering {
  private(set) var registrationCount = 0

  func registerForRemoteNotifications() {
    registrationCount += 1
  }
}

@MainActor
private final class NotificationStateFake: NotificationStateStoring {
  var insightNotificationsEnabled: Bool
  var deviceToken: String?
  private(set) var subscriptionState: StoredPushSubscriptionState
  var legacySubscriptionID: UUID?
  var registrationError: String?
  var pendingInsightID: String?
  var loadError: (any Error)?
  var saveFailuresRemaining: Int

  init(
    insightNotificationsEnabled: Bool = false,
    deviceToken: String? = nil,
    subscriptionState: StoredPushSubscriptionState = StoredPushSubscriptionState(),
    legacySubscriptionID: UUID? = nil,
    registrationError: String? = nil,
    pendingInsightID: String? = nil,
    loadError: (any Error)? = nil,
    saveFailuresRemaining: Int = 0
  ) {
    self.insightNotificationsEnabled = insightNotificationsEnabled
    self.deviceToken = deviceToken
    self.subscriptionState = subscriptionState
    self.legacySubscriptionID = legacySubscriptionID
    self.registrationError = registrationError
    self.pendingInsightID = pendingInsightID
    self.loadError = loadError
    self.saveFailuresRemaining = saveFailuresRemaining
  }

  func loadSubscriptionState() throws -> StoredPushSubscriptionState {
    if let loadError { throw loadError }
    return subscriptionState
  }

  func saveSubscriptionState(_ state: StoredPushSubscriptionState) throws {
    if saveFailuresRemaining > 0 {
      saveFailuresRemaining -= 1
      throw NotificationStateStoreError.persistenceFailed
    }
    subscriptionState = state
  }
}

@MainActor
private final class PushSubscriptionSpy {
  static let subscriptionID = UUID(uuidString: "00000000-0000-4000-8000-000000000802")!

  var registerError: (any Error)?
  var unregisterError: (any Error)?
  private(set) var registrations: [Registration] = []
  var unregistrations: [UUID] = []

  init(
    registerError: (any Error)? = nil,
    unregisterError: (any Error)? = nil
  ) {
    self.registerError = registerError
    self.unregisterError = unregisterError
  }

  var operations: PushSubscriptionOperations {
    PushSubscriptionOperations(
      register: { [self] token, environment in
        registrations.append(Registration(token: token, environment: environment))
        if let registerError { throw registerError }
        return Self.subscriptionID
      },
      unregister: { [self] identifier in
        unregistrations.append(identifier)
        if let unregisterError { throw unregisterError }
      }
    )
  }
}

@MainActor
private final class SuspendedRegistration {
  private(set) var callCount = 0
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var completion: CheckedContinuation<UUID, Never>?

  func register(token: String, environment: APNsEnvironment) async -> UUID {
    callCount += 1
    let waiters = startWaiters
    startWaiters.removeAll()
    waiters.forEach { $0.resume() }
    return await withCheckedContinuation { continuation in
      completion = continuation
    }
  }

  func waitUntilStarted() async {
    guard callCount == 0 else { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func complete(with identifier: UUID) {
    completion?.resume(returning: identifier)
    completion = nil
  }
}

@MainActor
private final class MainActorSignal {
  private var isSignaled = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func signal() {
    isSignaled = true
    let waiters = waiters
    self.waiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  func wait() async {
    guard !isSignaled else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
}
