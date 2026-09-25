import Foundation

/// Diagnoses common event-level failures against the pinned Rails Payload validator.
/// This is not a replacement for server validation and never alters queued bytes.
struct FinanceKitRejectedBatchInspector {
  func inspect(_ body: Data) -> FinanceKitEventValidationIssue? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
    }
    guard let payload = try? decoder.decode(FinanceKitBatchPayload.self, from: body) else {
      return .init(eventIndex: nil, field: .batch, rule: .readablePayload)
    }
    return inspect(events: payload.events, capturedAt: payload.capturedAt)
  }

  func inspect(events: [FinanceKitSourceEvent], capturedAt: Date) -> FinanceKitEventValidationIssue? {
    var identities: Set<Identity> = []
    for (index, event) in events.enumerated() {
      func issue(_ field: FinanceKitEventValidationIssue.Field,
                 _ rule: FinanceKitEventValidationIssue.Rule) -> FinanceKitEventValidationIssue {
        .init(eventIndex: index, field: field, rule: rule)
      }
      func text(_ value: String, _ field: FinanceKitEventValidationIssue.Field,
                limit: Int, allowsEmpty: Bool = false) -> FinanceKitEventValidationIssue? {
        if !allowsEmpty && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return issue(field, .nonblank)
        }
        // Ruby String#length counts Unicode code points, not grapheme clusters.
        return value.unicodeScalars.count > limit ? issue(field, .textLimit(limit)) : nil
      }
      let identity: Identity
      switch event {
      case .transactionUpsert(let record):
        if record.status == "booked", record.postedAt == nil { return issue(.postedAt, .requiredForBooked) }
        if !["authorized", "pending", "booked", "rejected", "memo", "unknown"].contains(record.status) {
          return issue(.status, .supportedStatus)
        }
        if let failure = text(record.transactionDescription, .transactionDescription, limit: 1000, allowsEmpty: true)
          ?? text(record.originalTransactionDescription, .originalDescription, limit: 1000, allowsEmpty: true)
          ?? text(record.transactionType, .transactionType, limit: 100) { return failure }
        if let merchant = record.merchantName, let failure = text(merchant, .merchantName, limit: 255) { return failure }
        if record.transactedAt > capturedAt { return issue(.transactedAt, .notAfterCapture) }
        if let postedAt = record.postedAt, postedAt > capturedAt { return issue(.postedAt, .notAfterCapture) }
        identity = Identity(kind: "transaction", lineage: record.lineageID, source: record.sourceID)
      case .transactionTombstone(let record):
        identity = Identity(kind: "transaction", lineage: record.lineageID, source: record.sourceID)
      case .accountUpsert(let record):
        if let failure = text(record.displayName, .accountName, limit: 255)
          ?? text(record.institutionName, .institutionName, limit: 255) { return failure }
        if let description = record.accountDescription,
           let failure = text(description, .accountDescription, limit: 1000, allowsEmpty: true) { return failure }
        identity = Identity(kind: "account", lineage: record.lineageID, source: record.sourceID)
      case .accountUnavailable(let source, let lineage, _):
        identity = Identity(kind: "account_unavailable", lineage: lineage, source: source)
      case .balanceUpsert(let record):
        if record.observedAt > capturedAt { return issue(.observedAt, .notAfterCapture) }
        identity = Identity(kind: "balance", lineage: record.lineageID, source: record.sourceID,
          balanceKind: record.kind, observedAt: record.observedAt)
      }
      if !identities.insert(identity).inserted { return issue(.identity, .uniqueIdentity) }
    }
    return nil
  }

  private struct Identity: Hashable {
    var kind: String
    var lineage: UUID
    var source: UUID
    var balanceKind: FinanceKitSourceBalance.Kind? = nil
    var observedAt: Date? = nil
  }
}
