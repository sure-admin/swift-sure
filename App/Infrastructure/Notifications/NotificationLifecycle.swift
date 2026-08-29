import Foundation

enum NotificationAuthorizationState: Equatable {
  case notDetermined
  case denied
  case authorized
}

@MainActor
protocol NotificationAuthorizationProviding: AnyObject {
  func status() async -> NotificationAuthorizationState
  func requestAuthorization() async throws -> Bool
  func clearBadge() async
}

@MainActor
protocol RemoteNotificationRegistering: AnyObject {
  func registerForRemoteNotifications()
}

@MainActor
protocol NotificationStateStoring: AnyObject {
  var insightNotificationsEnabled: Bool { get set }
  var deviceToken: String? { get set }
  var legacySubscriptionID: UUID? { get set }
  var registrationError: String? { get set }
  var pendingInsightID: String? { get set }
  func loadSubscriptionState() throws -> StoredPushSubscriptionState
  func saveSubscriptionState(_ state: StoredPushSubscriptionState) throws
}

struct PushSubscriptionOperations {
  var register: @MainActor (String, APNsEnvironment) async throws -> UUID
  var unregister: @MainActor (UUID) async throws -> Void
}

struct StoredPushSubscription: Codable, Equatable, Sendable {
  var id: UUID
  var serverURL: URL
  var deviceToken: String
  var environment: APNsEnvironment

  init(
    id: UUID,
    serverURL: URL,
    deviceToken: String,
    environment: APNsEnvironment
  ) throws {
    guard !deviceToken.isEmpty else {
      throw StoredPushSubscriptionError.invalidDeviceToken
    }

    self.id = id
    self.serverURL = try SureRequestContext(
      baseURL: serverURL,
      authorization: nil
    ).baseURL
    self.deviceToken = deviceToken
    self.environment = environment
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        id: values.decode(UUID.self, forKey: .id),
        serverURL: values.decode(URL.self, forKey: .serverURL),
        deviceToken: values.decode(String.self, forKey: .deviceToken),
        environment: values.decode(APNsEnvironment.self, forKey: .environment)
      )
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .serverURL,
        in: values,
        debugDescription: "The stored push subscription is invalid."
      )
    }
  }
}

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

enum StoredPushSubscriptionError: Error, Equatable {
  case invalidDeviceToken
}

enum NotificationStateStoreError: LocalizedError, Equatable {
  case invalidStoredState
  case persistenceFailed

  var errorDescription: String? {
    switch self {
    case .invalidStoredState:
      "The stored notification subscription is invalid."
    case .persistenceFailed:
      "The notification subscription could not be saved securely."
    }
  }
}

@MainActor
protocol AuthenticationNotificationLifecycle: AnyObject {
  func didConnect() async
  func prepareForConnectionChange() async
  func prepareForLogout() async
}

@MainActor
protocol RemoteNotificationEventHandling: AnyObject {
  func applicationDidFinishLaunching() async
  func receiveDeviceToken(_ token: String) async
  func receiveRemoteRegistrationFailure(_ error: Error)
  func receiveNotificationResponse(insightID: String?) async
}
