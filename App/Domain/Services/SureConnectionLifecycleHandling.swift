import Foundation

@MainActor
protocol SureConnectionLifecycleHandling: AnyObject {
  var dataCleanupFailure: DataFailure? { get }
  func didConnect() async
  func didCommitConnectionChange() async
  func prepareForConnectionChange() async
  func prepareForLogout() async
  func didLogOut()
}

extension SureConnectionLifecycleHandling {
  var dataCleanupFailure: DataFailure? { nil }
  func didCommitConnectionChange() async { }
}

