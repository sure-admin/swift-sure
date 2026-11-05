import Foundation

/// Reads and writes the widget snapshot in the App Group shared by the app and
/// the widget extension.
struct AccountsWidgetSnapshotStore: Sendable {
  static let fileName = "accounts-widget-snapshot.json"
  /// Info.plist key naming the App Group, so re-signed builds can use another group.
  static let appGroupInfoKey = "SureWidgetAppGroup"

  /// The App Group container, or nil when this build has no usable group.
  let directory: URL?

  init(directory: URL?) {
    self.directory = directory
  }

  static func appGroup(bundle: Bundle = .main) -> AccountsWidgetSnapshotStore {
    let group = bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String
    let directory = group.flatMap {
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
    }
    return AccountsWidgetSnapshotStore(directory: directory)
  }

  private var fileURL: URL? {
    directory?.appendingPathComponent(Self.fileName, isDirectory: false)
  }

  /// The saved snapshot; nil when there is none or it can't be read as the current version.
  func load() -> AccountsWidgetSnapshot? {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
    guard let snapshot = try? Self.decoder.decode(AccountsWidgetSnapshot.self, from: data),
          snapshot.version == AccountsWidgetSnapshot.currentVersion else { return nil }
    return snapshot
  }

  func save(_ snapshot: AccountsWidgetSnapshot) throws {
    guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
    let data = try Self.encoder.encode(snapshot)
    // Readable after the first unlock since boot, so the widget can render
    // while the device is locked; still encrypted before that.
    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  func remove() throws {
    guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
    try FileManager.default.removeItem(at: fileURL)
  }

  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
