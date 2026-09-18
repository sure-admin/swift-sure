import Foundation

actor FinanceKitPublisherStateFileStore: FinanceKitPublisherStateStoring {
  private var fileURL: URL
  private var fileManager: FileManager

  init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  func load() async throws -> FinanceKitPublisherState {
    guard fileManager.fileExists(atPath: fileURL.path) else { return .empty }
    do {
      let data = try Data(contentsOf: fileURL)
      let state = try JSONDecoder().decode(FinanceKitPublisherState.self, from: data)
      guard state.schemaVersion == FinanceKitPublisherState.currentSchemaVersion,
            state.nextSequence > 0,
            state.pendingCapture.map({ $0.nextBatchIndex <= $0.batches.count }) ?? true else {
        throw FinanceKitSyncError.invalidState
      }
      return state
    } catch let error as FinanceKitSyncError {
      throw error
    } catch {
      throw FinanceKitSyncError.invalidState
    }
  }

  func save(_ state: FinanceKitPublisherState) async throws {
    guard state.schemaVersion == FinanceKitPublisherState.currentSchemaVersion else {
      throw FinanceKitSyncError.invalidState
    }
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let data = try JSONEncoder().encode(state)
    #if os(iOS)
    try data.write(
      to: fileURL,
      options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    )
    #else
    try data.write(to: fileURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    #endif
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var protectedURL = fileURL
    try protectedURL.setResourceValues(values)
  }

  func clear() async throws {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    try fileManager.removeItem(at: fileURL)
  }
}
