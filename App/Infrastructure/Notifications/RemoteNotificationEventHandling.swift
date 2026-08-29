@MainActor
protocol RemoteNotificationEventHandling: AnyObject {
  func applicationDidFinishLaunching() async
  func receiveDeviceToken(_ token: String) async
  func receiveRemoteRegistrationFailure(_ error: Error)
  func receiveNotificationResponse(insightID: String?) async
}
