import Foundation

struct FinanceKitPublisherRevocationStore: Sendable {
  var fileURL: URL

  var isRevoked: Bool {
    FileManager.default.fileExists(atPath: fileURL.path)
  }

  func revoke() throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let marker = Data("revoked".utf8)
    #if os(iOS)
    try marker.write(
      to: fileURL,
      options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    )
    #else
    try marker.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
    #endif
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var protectedURL = fileURL
    try protectedURL.setResourceValues(values)
  }

  func clear() throws {
    guard isRevoked else { return }
    try FileManager.default.removeItem(at: fileURL)
  }
}
