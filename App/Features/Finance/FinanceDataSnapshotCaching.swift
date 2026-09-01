import Foundation

@MainActor
protocol FinanceDataSnapshotCaching {
  func loadSnapshotData() throws -> Data?
  func saveSnapshotData(_ data: Data) throws
  func removeSnapshotData() throws
}
