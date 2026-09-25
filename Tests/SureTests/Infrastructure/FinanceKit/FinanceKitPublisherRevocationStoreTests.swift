import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit publisher revocation")
struct FinanceKitPublisherRevocationStoreTests {
  @Test("A revocation marker persists until a new publisher clears it")
  func persistedMarker() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("financekit-revocation-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("revoked")
    let first = FinanceKitPublisherRevocationStore(fileURL: url)

    #expect(!first.isRevoked)
    try first.revoke()
    #expect(first.isRevoked)
    #expect(FinanceKitPublisherRevocationStore(fileURL: url).isRevoked)

    try first.clear()
    #expect(!first.isRevoked)
  }
}
