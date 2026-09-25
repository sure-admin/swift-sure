import Foundation
import Testing
@testable import Sure

@Suite("Application data reset")
struct ApplicationDataResetterTests {
  @Test("Logout removes app preferences, secrets, and downloaded files")
  func clearsLocalState() throws {
    let domain = "sure-reset-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain, isDirectory: true)
    defer {
      defaults.removePersistentDomain(forName: domain)
      try? FileManager.default.removeItem(at: directory)
    }
    defaults.set(true, forKey: "sureFirstRunCompleted")
    defaults.set("https://sure.example", forKey: "sureServerURL")
    defaults.set(true, forKey: "financeKitSyncConsentAcknowledged")
    let appDirectory = directory.appendingPathComponent("am.sure.insights", isDirectory: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    try Data("private".utf8).write(to: appDirectory.appendingPathComponent("finance-overview-snapshot.json"))
    var didClearSecrets = false
    let resetter = ApplicationDataResetter(defaults: defaults, domain: domain,
      appSupportDirectory: directory, clearSecrets: { didClearSecrets = true })

    try resetter.reset()

    #expect(didClearSecrets)
    #expect(!defaults.bool(forKey: "sureFirstRunCompleted"))
    #expect(defaults.string(forKey: "sureServerURL") == nil)
    #expect(defaults.object(forKey: "financeKitSyncConsentAcknowledged") == nil)
    #expect(!FileManager.default.fileExists(atPath: appDirectory.path))
  }

  @Test("Other cleanup continues if secret deletion fails")
  func continuesAfterSecretFailure() throws {
    let domain = "sure-reset-failure-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(true, forKey: "sureFirstRunCompleted")
    let resetter = ApplicationDataResetter(defaults: defaults, domain: domain,
      clearSecrets: { throw DataFailure.cleanup })

    #expect(throws: DataFailure.cleanup) { try resetter.reset() }
    #expect(!defaults.bool(forKey: "sureFirstRunCompleted"))
  }
}
