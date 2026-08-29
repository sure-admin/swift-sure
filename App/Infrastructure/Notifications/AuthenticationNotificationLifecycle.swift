@MainActor
protocol AuthenticationNotificationLifecycle: AnyObject {
  func didConnect() async
  func prepareForConnectionChange() async
  func prepareForLogout() async
}
