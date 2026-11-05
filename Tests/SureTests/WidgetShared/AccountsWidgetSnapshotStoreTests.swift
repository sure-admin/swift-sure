import Foundation
import Testing
@testable import Sure

@Suite("Accounts widget snapshot store")
struct AccountsWidgetSnapshotStoreTests {
  private let snapshot = AccountsWidgetSnapshot(
    accounts: [.init(id: "1", name: "Checking", institution: "Bank", balance: "$100.00", isLiability: false)],
    netWorth: "$100.00",
    updatedAt: testReadDate
  )

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("AccountsWidgetSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("A saved snapshot loads back unchanged")
  func roundTrip() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AccountsWidgetSnapshotStore(directory: directory)
    try store.save(snapshot)
    #expect(store.load() == snapshot)
  }

  @Test("Removing the snapshot leaves nothing to load, and removing twice is harmless")
  func remove() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AccountsWidgetSnapshotStore(directory: directory)
    try store.save(snapshot)
    try store.remove()
    #expect(store.load() == nil)
    try store.remove()
  }

  @Test("Files from another snapshot version are ignored")
  func otherVersion() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AccountsWidgetSnapshotStore(directory: directory)
    var future = snapshot
    future.version = AccountsWidgetSnapshot.currentVersion + 1
    try store.save(future)
    #expect(store.load() == nil)
  }

  @Test("Malformed files are ignored")
  func malformed() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("not json".utf8).write(to: directory.appendingPathComponent(AccountsWidgetSnapshotStore.fileName))
    #expect(AccountsWidgetSnapshotStore(directory: directory).load() == nil)
  }

  @Test("Without an App Group container nothing loads and saving fails")
  func missingContainer() throws {
    let store = AccountsWidgetSnapshotStore(directory: nil)
    #expect(store.load() == nil)
    #expect(throws: (any Error).self) { try store.save(snapshot) }
    try store.remove()
  }
}
