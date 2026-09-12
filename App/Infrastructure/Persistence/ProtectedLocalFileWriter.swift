import Foundation

struct ProtectedLocalFileWriter {
  var fileManager: FileManager = .default

  func write(_ data: Data, to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    #if os(macOS)
    // iOS data-protection flags are not usable for native Mac file writes.
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try data.write(to: url, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    #else
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    #endif
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var protectedURL = url
    try protectedURL.setResourceValues(values)
  }
}
