import SwiftUI

@main
struct AppDefinition: App {
  #if os(iOS)
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #endif

  var body: some Scene {
    WindowGroup {
      // Unit test hosts must not construct Keychain, FinanceKit, StoreKit,
      // analytics, notification, or Watch services as a side effect of launch.
      if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
        Color.clear
      } else {
        ApplicationView { notifications, gate in
          #if os(iOS)
          appDelegate.notificationEventHandler = notifications
          appDelegate.canReceiveBackendNotifications = { gate.isAllowed }
          #endif
        }
      }
    }
  }
}
