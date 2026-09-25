import Foundation

struct FinanceKitCollectedChanges: Equatable, Sendable {
  var mode: FinanceKitCaptureMode
  var capturedAt: Date
  var events: [FinanceKitSourceEvent]
  var nextCheckpoint: Data
}
