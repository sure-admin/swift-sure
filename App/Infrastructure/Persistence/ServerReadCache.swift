import CryptoKit
import Foundation

/// One disk format and retention policy for complete, validated server reads.
actor ServerReadCache {
  struct Entry: Codable, Sendable {
    var version = 1
    var fetchedAt: Date
    var payload: Data
  }
  private let directory: URL
  private let maximumEntries: Int
  private let maximumBytes: Int
  private var epoch = 0

  init(directory: URL, maximumEntries: Int = 256, maximumBytes: Int = 64 * 1_024 * 1_024) {
    self.directory = directory
    self.maximumEntries = maximumEntries
    self.maximumBytes = maximumBytes
  }

  func lease() -> Int { epoch }

  func read(scope: String, key: String) throws -> Entry? {
    let url = fileURL(scope: scope, key: key)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    guard data.count <= maximumBytes,
          let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.version == 1 else {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
    return entry
  }

  func write(_ entry: Entry, scope: String, key: String, lease: Int) throws {
    guard lease == epoch else { throw CancellationError() }
    let data = try JSONEncoder().encode(entry)
    guard data.count <= maximumBytes else { throw DataFailure.persistence }
    try ProtectedLocalFileWriter().write(data, to: fileURL(scope: scope, key: key))
    try prune()
  }

  func removeAll() throws {
    // In-flight reads hold the previous lease and cannot recreate erased data.
    epoch &+= 1
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  func migrateLegacySnapshot(at url: URL, server: URL, identity: String, lease: Int) throws {
    guard lease == epoch else { throw CancellationError() }
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let data = try Data(contentsOf: url)
    let snapshot = try FinanceDataSnapshotCodec().decode(data)
    guard snapshot.serverURL == server, snapshot.connectionIdentity == identity,
          let date = snapshot.lastUpdated else { return }
    let scope = server.absoluteString + "\n" + identity
    // Legacy snapshots did not record query completeness. Their transactions may
    // hydrate a preview, but must never satisfy an exact transaction-window read.
    for key in ["balance-sheet", "accounts", "budgets", "insights", "legacy-preview"] {
      if try read(scope: scope, key: key) == nil {
        try write(Entry(fetchedAt: date, payload: data), scope: scope, key: key, lease: epoch)
      }
    }
    try FileManager.default.removeItem(at: url)
  }

  func removeLegacyFiles(_ urls: [URL]) throws {
    for url in urls where FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private func fileURL(scope: String, key: String) -> URL {
    let digest = SHA256.hash(data: Data((scope + "\n" + key).utf8))
      .map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(digest)
  }

  private func prune() throws {
    let files = try FileManager.default.contentsOfDirectory(at: directory,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
    let entries = try files.map { url in
      (url, try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]))
    }.sorted { ($0.1.contentModificationDate ?? .distantPast) < ($1.1.contentModificationDate ?? .distantPast) }
    var count = entries.count
    var bytes = entries.reduce(0) { $0 + ($1.1.fileSize ?? 0) }
    for (url, values) in entries where count > maximumEntries || bytes > maximumBytes {
      try FileManager.default.removeItem(at: url)
      count -= 1; bytes -= values.fileSize ?? 0
    }
  }
}
