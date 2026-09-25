/// Safe protocol diagnostics from the pinned FinanceKit validator. Unknown server
/// text must never be persisted or displayed: it may contain financial data.
enum FinanceKitBatchRejection: String, Codable, Equatable, Sendable {
  case invalidPayload = "invalid_payload"
  case invalidTimestamp = "invalid_timestamp"
  case invalidCurrency = "invalid_currency"
  case currencyMismatch = "currency_mismatch"
  case duplicateRecord = "duplicate_record"
  case futureCapture = "future_capture"
  case invalidPredecessor = "invalid_predecessor"
  case unknown

  init(serverCode: String?) {
    self = serverCode.flatMap(Self.init(rawValue:)) ?? .unknown
  }
}
