import CryptoKit
import Foundation

/// Stores authenticated read responses only. Keys contain no credentials or URLs;
/// each namespace is tied to the committed server and credential identity.
actor OfflineAPIResponseStore: OfflineResponseStoring {
  private var directory: URL
  init(directory: URL) { self.directory = directory }

  func read(key: String) throws -> Data? {
    let url = fileURL(key)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try Data(contentsOf: url)
  }

  func write(_ data: Data, key: String) throws {
    try ProtectedLocalFileWriter().write(data, to: fileURL(key))
  }

  func removeAll() throws {
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  private func fileURL(_ key: String) -> URL {
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(digest)
  }
}

protocol OfflineResponseStoring: Sendable {
  func read(key: String) async throws -> Data?
  func write(_ data: Data, key: String) async throws
  func removeAll() async throws
}
