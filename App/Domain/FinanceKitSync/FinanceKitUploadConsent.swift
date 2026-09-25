import Foundation

struct FinanceKitUploadConsent: Codable, Equatable, Sendable {
  static let currentVersion = 1

  var version: Int
  var grantedAt: Date
  var selectedSourceAccountIDs: [UUID]
  var uploadAuthorized: Bool
  var familyVisibilityAcknowledged: Bool
  var remoteProcessingAcknowledged: Bool

  init(
    version: Int = Self.currentVersion,
    grantedAt: Date,
    selectedSourceAccountIDs: [UUID],
    uploadAuthorized: Bool,
    familyVisibilityAcknowledged: Bool,
    remoteProcessingAcknowledged: Bool
  ) throws {
    let selected = selectedSourceAccountIDs.sorted { $0.uuidString < $1.uuidString }
    guard version == Self.currentVersion,
          !selected.isEmpty,
          Set(selected).count == selected.count,
          uploadAuthorized,
          familyVisibilityAcknowledged,
          remoteProcessingAcknowledged else {
      throw FinanceKitPublisherConfigurationError.invalidConsent
    }
    self.version = version
    self.grantedAt = grantedAt
    self.selectedSourceAccountIDs = selected
    self.uploadAuthorized = uploadAuthorized
    self.familyVisibilityAcknowledged = familyVisibilityAcknowledged
    self.remoteProcessingAcknowledged = remoteProcessingAcknowledged
  }

  private enum CodingKeys: String, CodingKey {
    case version, grantedAt = "granted_at", selectedSourceAccountIDs = "selected_source_account_ids"
    case uploadAuthorized = "upload_authorized", familyVisibilityAcknowledged = "family_visibility_acknowledged"
    case remoteProcessingAcknowledged = "remote_processing_acknowledged"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      version: container.decode(Int.self, forKey: .version),
      grantedAt: container.decode(Date.self, forKey: .grantedAt),
      selectedSourceAccountIDs: container.decode([UUID].self, forKey: .selectedSourceAccountIDs),
      uploadAuthorized: container.decode(Bool.self, forKey: .uploadAuthorized),
      familyVisibilityAcknowledged: container.decode(Bool.self, forKey: .familyVisibilityAcknowledged),
      remoteProcessingAcknowledged: container.decode(Bool.self, forKey: .remoteProcessingAcknowledged)
    )
  }
}
