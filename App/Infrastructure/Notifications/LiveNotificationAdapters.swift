import Foundation
import UserNotifications

#if os(iOS)
import UIKit
#endif

@MainActor
final class SystemNotificationAuthorizationProvider: NotificationAuthorizationProviding {
  private var center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func status() async -> NotificationAuthorizationState {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      .authorized
    case .notDetermined:
      .notDetermined
    case .denied:
      .denied
    @unknown default:
      .denied
    }
  }

  func requestAuthorization() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .badge, .sound])
  }

  func clearBadge() async {
    try? await center.setBadgeCount(0)
  }
}

@MainActor
final class SystemRemoteNotificationRegistrar: RemoteNotificationRegistering {
  func registerForRemoteNotifications() {
    #if os(iOS)
    UIApplication.shared.registerForRemoteNotifications()
    #endif
  }
}

@MainActor
final class LiveNotificationStateStore: NotificationStateStoring {
  private var defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var insightNotificationsEnabled: Bool {
    get { defaults.bool(forKey: StorageKey.insightsEnabled) }
    set { defaults.set(newValue, forKey: StorageKey.insightsEnabled) }
  }

  var deviceToken: String? {
    get { KeychainStore.read(account: StorageKey.deviceToken) }
    set { KeychainStore.save(newValue ?? "", account: StorageKey.deviceToken) }
  }

  func loadSubscriptionState() throws -> StoredPushSubscriptionState {
    guard let encoded = KeychainStore.read(account: StorageKey.subscriptionState)
    else { return StoredPushSubscriptionState() }
    guard let data = encoded.data(using: .utf8),
          let state = try? JSONDecoder().decode(StoredPushSubscriptionState.self, from: data)
    else { throw NotificationStateStoreError.invalidStoredState }
    return state
  }

  func saveSubscriptionState(_ state: StoredPushSubscriptionState) throws {
    guard let data = try? JSONEncoder().encode(state),
          let encoded = String(data: data, encoding: .utf8),
          KeychainStore.save(encoded, account: StorageKey.subscriptionState)
    else { throw NotificationStateStoreError.persistenceFailed }
  }

  var legacySubscriptionID: UUID? {
    get {
      guard let identifier = KeychainStore.read(account: StorageKey.legacySubscriptionID)
      else { return nil }
      guard let identifier = UUID(uuidString: identifier) else {
        KeychainStore.remove(StorageKey.legacySubscriptionID)
        return nil
      }
      return identifier
    }
    set {
      KeychainStore.save(
        newValue?.uuidString.lowercased() ?? "",
        account: StorageKey.legacySubscriptionID
      )
    }
  }

  var registrationError: String? {
    get { defaults.string(forKey: StorageKey.registrationError) }
    set {
      if let newValue {
        defaults.set(newValue, forKey: StorageKey.registrationError)
      } else {
        defaults.removeObject(forKey: StorageKey.registrationError)
      }
    }
  }

  var pendingInsightID: String? {
    get { defaults.string(forKey: StorageKey.pendingInsightID) }
    set {
      if let newValue {
        defaults.set(newValue, forKey: StorageKey.pendingInsightID)
      } else {
        defaults.removeObject(forKey: StorageKey.pendingInsightID)
      }
    }
  }

  private enum StorageKey {
    static let deviceToken = "apnsDeviceToken"
    static let subscriptionState = "pushSubscriptionState.v2"
    static let legacySubscriptionID = "pushSubscriptionID"
    static let insightsEnabled = "insightNotificationsEnabled"
    static let registrationError = "pushRegistrationError"
    static let pendingInsightID = "pendingInsightID"
  }
}
