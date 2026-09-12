#if os(iOS)
import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  var canReceiveBackendNotifications: () -> Bool = { false }
  weak var notificationEventHandler: (any RemoteNotificationEventHandling)?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    Task { @MainActor [weak self] in
      guard self?.canReceiveBackendNotifications() == true else { return }
      await self?.notificationEventHandler?.applicationDidFinishLaunching()
    }
    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = APNsDeviceTokenFormatter.string(from: deviceToken)
    Task { @MainActor [weak self] in
      await self?.notificationEventHandler?.receiveDeviceToken(token)
    }
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    notificationEventHandler?.receiveRemoteRegistrationFailure(error)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    canReceiveBackendNotifications() ? [.banner, .sound, .badge] : []
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard canReceiveBackendNotifications() else { return }
    let insightID = response.notification.request.content.userInfo["insight_id"] as? String
    await notificationEventHandler?.receiveNotificationResponse(insightID: insightID)
  }
}
#endif
