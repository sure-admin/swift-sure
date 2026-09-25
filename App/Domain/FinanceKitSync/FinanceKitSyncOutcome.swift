enum FinanceKitSyncOutcome: Equatable, Sendable {
  case notConfigured
  case busy
  case noChanges
  case uploaded(Int)
  case repairRequired
}
