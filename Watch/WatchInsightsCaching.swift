import Foundation

protocol WatchInsightsCaching {
  func loadSnapshotData() throws -> Data?
  func saveSnapshotData(_ data: Data) throws
}
