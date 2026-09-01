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
    let directoryURL = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: [.atomic, .completeFileProtection])

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var protectedFileURL = fileURL
    try protectedFileURL.setResourceValues(resourceValues)
  }

  func removeSnapshotData() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    try fileManager.removeItem(at: fileURL)
  }
}
