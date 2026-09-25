import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit rejected event diagnostics")
struct FinanceKitRejectedBatchInspectorTests {
  private let inspector = FinanceKitRejectedBatchInspector()

  @Test("A persisted booked transaction without posted_at identifies the precise field")
  func bookedWithoutDate() throws {
    let body = try APIFixture.data(named: "financekit-booked-missing-posted-at")
    #expect(inspector.inspect(body) == .init(eventIndex: 0, field: .postedAt, rule: .requiredForBooked))
  }

  @Test("Only booked transactions require a posting date", arguments: ["authorized", "pending", "memo", "rejected", "unknown"])
  func optionalDate(status: String) throws {
    var record = try transaction()
    record.status = status
    #expect(inspector.inspect(events: [.transactionUpsert(record)], capturedAt: .distantFuture) == nil)
  }

  @Test("A real posting date satisfies the booked requirement without changing the source record")
  func bookedWithDate() throws {
    var record = try transaction()
    record.postedAt = record.transactedAt.addingTimeInterval(60)
    #expect(inspector.inspect(events: [.transactionUpsert(record)], capturedAt: .distantFuture) == nil)
  }

  @Test("Unsupported status, blank merchant and text limits are separate diagnostics")
  func textRules() throws {
    var record = try transaction()
    record.status = "unsupported"
    #expect(inspector.inspect(events: [.transactionUpsert(record)], capturedAt: .distantFuture)?.field == .status)
    record.status = "pending"
    record.merchantName = " \n"
    #expect(inspector.inspect(events: [.transactionUpsert(record)], capturedAt: .distantFuture) ==
      .init(eventIndex: 0, field: .merchantName, rule: .nonblank))
    record.merchantName = nil
    record.transactionDescription = String(repeating: "e\u{301}", count: 501)
    #expect(inspector.inspect(events: [.transactionUpsert(record)], capturedAt: .distantFuture) ==
      .init(eventIndex: 0, field: .transactionDescription, rule: .textLimit(1000)))
    record.transactionDescription = String(repeating: "a", count: 1000)
    #expect(inspector.inspect(events: [.transactionUpsert(record)], capturedAt: .distantFuture) == nil)
  }

  @Test("Transaction and posting dates cannot follow capture, but equality is allowed")
  func futureDates() throws {
    var record = try transaction()
    record.status = "pending"
    #expect(inspector.inspect(events: [.transactionUpsert(record)], capturedAt: record.transactedAt)?.field == nil)
    #expect(inspector.inspect(events: [.transactionUpsert(record)], capturedAt: record.transactedAt.addingTimeInterval(-1))?.field == .transactedAt)
    record.postedAt = record.transactedAt.addingTimeInterval(1)
    #expect(inspector.inspect(events: [.transactionUpsert(record)], capturedAt: record.transactedAt)?.field == .postedAt)
  }

  @Test("An upsert and tombstone for the same lineage and source collide")
  func duplicateIdentity() throws {
    var record = try transaction()
    record.status = "pending"
    let tombstone = FinanceKitSourceTransactionTombstone(sourceID: record.sourceID,
      sourceAccountID: record.sourceAccountID, lineageID: record.lineageID, mappingVersion: 1)
    #expect(inspector.inspect(events: [.transactionUpsert(record), .transactionTombstone(tombstone)], capturedAt: .distantFuture) ==
      .init(eventIndex: 1, field: .identity, rule: .uniqueIdentity))
  }

  @Test("Available and booked balances sharing a source identifier remain distinct")
  func balanceIdentity() throws {
    let record = try transaction()
    let balance = FinanceKitSourceBalance(sourceID: record.sourceID, sourceAccountID: record.sourceAccountID,
      lineageID: record.lineageID, mappingVersion: 1, kind: .available, observedAt: record.transactedAt, money: record.amount)
    var booked = balance
    booked.kind = .booked
    #expect(inspector.inspect(events: [.balanceUpsert(balance), .balanceUpsert(booked)], capturedAt: .distantFuture) == nil)
    #expect(inspector.inspect(events: [.balanceUpsert(balance)], capturedAt: .distantPast)?.field == .observedAt)
  }

  @Test("Unrecognized saved payloads expose no raw data")
  func malformedPayload() {
    #expect(inspector.inspect(Data("private unexpected content".utf8)) ==
      .init(eventIndex: nil, field: .batch, rule: .readablePayload))
  }

  private func transaction() throws -> FinanceKitSourceTransaction {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(FinanceKitBatchPayload.self,
      from: APIFixture.data(named: "financekit-booked-missing-posted-at"))
    guard case .transactionUpsert(let record) = payload.events[0] else {
      throw FinanceKitSyncError.invalidState
    }
    return record
  }
}
