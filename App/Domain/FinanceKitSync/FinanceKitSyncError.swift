enum FinanceKitSyncError: Error, Equatable {
  case eventTooLarge
  case historyTokenInvalid
  case invalidAmount
  case invalidCheckpoint
  case invalidReceipt
  case invalidState
  case sequenceExhausted
  case streamFailed
  case unsupportedSourceValue
}
