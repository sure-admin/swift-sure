import Foundation
import UserNotifications

#if os(iOS)
import UIKit
#endif

@MainActor
final class NotificationManager {
  static let shared = NotificationManager()

  func enableInsightNotifications() async -> Bool {
    #if os(iOS)
    do {
      let center = UNUserNotificationCenter.current()
      let settings = await center.notificationSettings()
      let authorized: Bool
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        authorized = true
      case .notDetermined:
        authorized = try await center.requestAuthorization(options: [.alert, .badge, .sound])
      case .denied:
        authorized = false
      @unknown default:
        authorized = false
      }
      guard authorized else { return false }
      UIApplication.shared.registerForRemoteNotifications()
      await registerStoredDeviceTokenIfNeeded()
      return true
    } catch {
      record(error)
      return false
    }
    #else
    return false
    #endif
  }

  func disableInsightNotifications() async {
    guard let subscriptionID = KeychainStore.read(account: StorageKey.subscriptionID),
          SureConnection.shared.isConfigured else { return }
    do {
      try await SureAPIClient(connection: SureConnection.shared)
        .unregisterPushSubscription(id: subscriptionID)
      KeychainStore.save("", account: StorageKey.subscriptionID)
      UserDefaults.standard.removeObject(forKey: StorageKey.registrationError)
    } catch {
      record(error)
    }
  }

  func receiveDeviceToken(_ token: String) async {
    KeychainStore.save(token, account: StorageKey.deviceToken)
    await registerStoredDeviceTokenIfNeeded()
  }

  func registerStoredDeviceTokenIfNeeded() async {
    guard UserDefaults.standard.bool(forKey: StorageKey.insightsEnabled),
          SureConnection.shared.isConfigured,
          let token = KeychainStore.read(account: StorageKey.deviceToken) else { return }
    do {
      let subscriptionID = try await SureAPIClient(connection: SureConnection.shared)
        .registerPushSubscription(token: token, environment: .current)
      KeychainStore.save(subscriptionID, account: StorageKey.subscriptionID)
      UserDefaults.standard.removeObject(forKey: StorageKey.registrationError)
    } catch {
      record(error)
    }
  }

  private func record(_ error: Error) {
    UserDefaults.standard.set(error.localizedDescription, forKey: StorageKey.registrationError)
  }

  private enum StorageKey {
    static let deviceToken = "apnsDeviceToken"
    static let subscriptionID = "pushSubscriptionID"
    static let insightsEnabled = "insightNotificationsEnabled"
    static let registrationError = "pushRegistrationError"
  }
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    Task {
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) {
        application.registerForRemoteNotifications()
      }
    }
    return true
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    Task { await NotificationManager.shared.receiveDeviceToken(token) }
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    UserDefaults.standard.set(error.localizedDescription, forKey: "pushRegistrationError")
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .badge]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    if let insightID = response.notification.request.content.userInfo["insight_id"] as? String {
      UserDefaults.standard.set(insightID, forKey: "pendingInsightID")
    }
    try? await center.setBadgeCount(0)
  }
}
#endif
