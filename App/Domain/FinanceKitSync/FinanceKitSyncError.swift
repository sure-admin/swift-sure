enum FinanceKitSyncError: Error, Equatable {
  case eventTooLarge
  case historyTokenInvalid
  /// The server accepted the capture but has not imported it yet. The pending
  /// capture and the FinanceKit checkpoint are retained, so the next pass
  /// resumes polling instead of re-collecting.
  case importPending
  case invalidAmount
  case invalidCheckpoint
  case invalidReceipt
  case invalidState
  case sequenceExhausted
  case streamFailed
  case unsupportedSourceValue
}
