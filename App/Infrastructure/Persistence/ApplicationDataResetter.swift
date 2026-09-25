import Foundation

/// Removes app-owned local state after the authenticated logout has stopped sync.
/// System FinanceKit authorization and Wallet records are owned by iOS.
struct ApplicationDataResetter {
  var defaults: UserDefaults = .standard
  var domain: String = Bundle.main.bundleIdentifier ?? "am.sure.insights"
  var appSupportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  var fileManager: FileManager = .default
  var clearSecrets: () throws -> Void = { try KeychainStore.removeAllAppSecrets() }

  func reset() throws {
    var failure: Error?
    do { try clearSecrets() } catch { failure = error }
    defaults.removePersistentDomain(forName: domain)
    let appDirectory = appSupportDirectory.appendingPathComponent("am.sure.insights", isDirectory: true)
    if fileManager.fileExists(atPath: appDirectory.path) {
      do { try fileManager.removeItem(at: appDirectory) }
      catch { failure = error }
    }
    if failure != nil { throw DataFailure.cleanup }
  }
}
