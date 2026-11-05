#if os(iOS)
import Foundation
import Testing
@testable import Sure

@Suite("Accounts widget publisher")
@MainActor
struct AccountsWidgetPublisherTests {
  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("AccountsWidgetPublisherTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private var update: AccountsWidgetUpdate {
    AccountsWidgetUpdate(accounts: [testReadAccount], netWorth: nil, updatedAt: testReadDate)
  }

  @Test("An update is saved and the widget reloads")
  func publish() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var reloads = 0
    let store = AccountsWidgetSnapshotStore(directory: directory)
    let publisher = AccountsWidgetPublisher(store: store, locale: Locale(identifier: "en_US")) { reloads += 1 }
    publisher.publish(update)
    #expect(store.load()?.accounts.map(\.id) == [testReadAccount.id.uuidString])
    #expect(reloads == 1)
  }

  @Test("Clearing removes the snapshot and reloads the widget")
  func clear() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var reloads = 0
    let store = AccountsWidgetSnapshotStore(directory: directory)
    let publisher = AccountsWidgetPublisher(store: store) { reloads += 1 }
    publisher.publish(update)
    publisher.publish(nil)
    #expect(store.load() == nil)
    #expect(reloads == 2)
  }

  @Test("A failed write removes whatever was there instead of leaving it")
  func failedWrite() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // A directory at the snapshot path makes the atomic file write fail.
    let blocker = directory.appendingPathComponent(AccountsWidgetSnapshotStore.fileName, isDirectory: true)
    try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
    var reloads = 0
    let publisher = AccountsWidgetPublisher(store: AccountsWidgetSnapshotStore(directory: directory)) { reloads += 1 }
    publisher.publish(update)
    #expect(!FileManager.default.fileExists(atPath: blocker.path))
    #expect(reloads == 1)
  }
}
#endif
