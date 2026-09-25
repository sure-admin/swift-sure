import Foundation

/// The minimum durable information needed to retry revocation on the original server.
struct FinanceKitDisconnectTarget: Codable, Equatable, Sendable {
  var connectionID: UUID
  var serverURL: URL
}
