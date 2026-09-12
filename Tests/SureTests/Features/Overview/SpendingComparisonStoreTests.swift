import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Spending comparison state")
struct SpendingComparisonStoreTests {
  @Test("Starts in the current month even on the first three days")
  func initialMonth() throws {
    let store = makeStore()
    #expect(store.selectedMonth?.start.iso8601String == "2026-09-01")
    #expect(store.months.count == 12)
    #expect(store.months.last?.start.iso8601String == "2025-10-01")
  }

  @Test("Production service reports unavailable without inventing a zero series")
  func unavailable() async {
    let store = makeStore()
    await store.refresh()
    #expect(store.state == .unavailable)
  }

  @Test("An unconfigured connection does not request data")
  func disconnected() async {
    let client = ControlledSpendingClient()
    let store = makeStore(client: client, connection: SpendingConnectionStub(isConfigured: false))
    await store.refresh()
    #expect(store.state == .idle)
    #expect(await client.count == 0)
  }

  @Test("A response from a prior month cannot replace a newer selection")
  func staleSelection() async throws {
    let client = ControlledSpendingClient()
    let store = makeStore(client: client)
    var events = client.requests.makeAsyncIterator()
    let first = Task { await store.refresh() }
    let firstMonth = try #require(await events.next())
    let previousMonth = firstMonth.shifted(by: -1)
    let second = Task { await store.select(previousMonth) }
    _ = await events.next()
    await client.complete(previousMonth, result: .success(try comparison(previousMonth)))
    await second.value
    await client.complete(firstMonth, result: .success(try comparison(firstMonth)))
    await first.value
    #expect(store.selectedMonth == previousMonth)
    if case .loaded(let value) = store.state { #expect(value.month == previousMonth) }
    else { Issue.record("Expected the selected month's response") }
  }

  @Test("Disconnect invalidates an in-flight response")
  func invalidate() async throws {
    let client = ControlledSpendingClient()
    let store = makeStore(client: client)
    var events = client.requests.makeAsyncIterator()
    let task = Task { await store.refresh() }
    let month = try #require(await events.next())
    store.invalidate()
    await client.complete(month, result: .success(try comparison(month)))
    await task.value
    #expect(store.state == .idle)
  }

  @Test("Failures remain failures and cancellation returns to idle")
  func failuresAndCancellation() async throws {
    for cancelled in [false, true] {
      let client = ControlledSpendingClient()
      let store = makeStore(client: client)
      var events = client.requests.makeAsyncIterator()
      let task = Task { await store.refresh() }
      let month = try #require(await events.next())
      let error: any Error = cancelled ? CancellationError() : URLError(.badServerResponse)
      await client.complete(month, result: .failure(error))
      await task.value
      #expect(store.state == (cancelled ? .idle : .failed))
    }
  }

  @Test("A response for the wrong month is rejected")
  func wrongMonth() async throws {
    let client = ControlledSpendingClient()
    let store = makeStore(client: client)
    var events = client.requests.makeAsyncIterator()
    let task = Task { await store.refresh() }
    let month = try #require(await events.next())
    await client.complete(month, result: .success(try comparison(month.shifted(by: -1))))
    await task.value
    #expect(store.state == .failed)
  }

  private func makeStore(
    client: any SpendingComparisonClient = UnavailableSpendingComparisonClient(),
    connection: SpendingConnectionStub? = nil
  ) -> SpendingComparisonStore {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
    return SpendingComparisonStore(client: client, connection: connection ?? SpendingConnectionStub(), calendar: calendar, now: { now })
  }

  private func comparison(_ month: SpendingMonth) throws -> SpendingComparison {
    let asOf = try LocalDate(year: 2026, month: 9, day: 2)
    let previous = month.shifted(by: -1)
    return try SpendingComparison(
      month: month, asOf: asOf, currency: #require(CurrencyCode("USD")),
      current: (1...(month == SpendingMonth(containing: asOf) ? 2 : month.dayCount)).map {
        .init(date: try month.date(day: $0), amount: Decimal($0))
      },
      previous: (1...previous.dayCount).map { .init(date: try previous.date(day: $0), amount: Decimal($0)) }
    )
  }
}

@MainActor
private final class SpendingConnectionStub: ConnectionStateProviding {
  var isConfigured: Bool
  var sessionGeneration = 0
  init(isConfigured: Bool = true) { self.isConfigured = isConfigured }
}

private actor ControlledSpendingClient: SpendingComparisonClient {
  nonisolated let requests: AsyncStream<SpendingMonth>
  private let eventContinuation: AsyncStream<SpendingMonth>.Continuation
  private var pending: [SpendingMonth: CheckedContinuation<SpendingComparison, any Error>] = [:]
  private(set) var count = 0

  init() {
    let stream = AsyncStream<SpendingMonth>.makeStream()
    requests = stream.stream
    eventContinuation = stream.continuation
  }

  func fetchComparison(for month: SpendingMonth) async throws -> SpendingComparison {
    count += 1
    return try await withCheckedThrowingContinuation { continuation in
      pending[month] = continuation
      eventContinuation.yield(month)
    }
  }

  func complete(_ month: SpendingMonth, result: Result<SpendingComparison, any Error>) {
    pending.removeValue(forKey: month)?.resume(with: result)
  }
}
