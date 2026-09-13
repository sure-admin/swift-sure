import Foundation

struct FileFinanceDataSnapshotCache: FinanceDataSnapshotCaching {
  private var fileManager: FileManager
  private var fileURL: URL

  init(
    fileManager: FileManager = .default,
    applicationSupportURL: URL? = nil,
    bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "am.sure.insights"
  ) {
    self.fileManager = fileManager
    let applicationSupportURL = applicationSupportURL
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    fileURL = applicationSupportURL
      .appending(path: bundleIdentifier, directoryHint: .isDirectory)
      .appending(path: "finance-overview-snapshot.json", directoryHint: .notDirectory)
  }

  func loadSnapshotData() throws -> Data? {
    guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
    return try Data(contentsOf: fileURL)
  }

  func saveSnapshotData(_ data: Data) throws {
    try ProtectedLocalFileWriter(fileManager: fileManager).write(data, to: fileURL)
  }

  func removeSnapshotData() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    try fileManager.removeItem(at: fileURL)
  }
}
