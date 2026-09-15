import Foundation
import Observation

@MainActor
@Observable
final class SpendingComparisonStore {
  private(set) var metadata: ReadMetadata?
  private(set) var failure: DataFailure?
  private var storedState: State = .idle
  private var activeAccess: AccessIdentity?
  var state: State { activeAccess == accessIdentity ? storedState : .idle }
  var source: Source { connection.allowsWalletPreview && walletClient != nil && walletAccess?.walletSpendingAccess.isAuthorized == true ? .wallet : .sure }
  var accessIdentity: AccessIdentity {
    AccessIdentity(previewAllowed: connection.allowsWalletPreview, wallet: connection.allowsWalletPreview ? walletAccess?.walletSpendingAccess : nil, serverConfigured: connection.isConfigured, serverGeneration: connection.sessionGeneration)
  }
  private(set) var months: [SpendingMonth] = []
  private(set) var selectedMonth: SpendingMonth?

  private let walletClient: (any WalletSpendingComparisonProviding)?
  private let walletAccess: (any WalletSpendingAccessProviding)?
  private let client: any SpendingComparisonClient
  private let now: () -> Date
  private let calendar: Calendar
  private let connection: any ConnectionStateProviding
  private var generation = 0
  private var loadingMonth: SpendingMonth?
  private var refreshWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

  init(
    client: any SpendingComparisonClient,
    connection: any ConnectionStateProviding,
    calendar: Calendar,
    now: @escaping () -> Date,
    walletClient: (any WalletSpendingComparisonProviding)? = nil,
    walletAccess: (any WalletSpendingAccessProviding)? = nil
  ) {
    self.walletClient = walletClient
    self.walletAccess = walletAccess
    self.client = client
    self.connection = connection
    var reportingCalendar = Calendar(identifier: .gregorian)
    reportingCalendar.timeZone = calendar.timeZone
    self.calendar = reportingCalendar
    self.now = now
    updateMonths()
  }

  func select(_ month: SpendingMonth) async {
    guard months.contains(month), month != selectedMonth else { return }
    selectedMonth = month
    await refresh()
  }

  func refreshIfNeeded() async {
    if state == .idle || state == .loading { await refresh() }
  }

  func refresh() async {
    updateMonths()
    if state == .loading && loadingMonth == selectedMonth {
      let waitingGeneration = generation
      await withCheckedContinuation { continuation in
        refreshWaiters[waitingGeneration, default: []].append(continuation)
      }
      if generation == waitingGeneration && state == .idle && !Task.isCancelled {
        await refresh()
      }
      return
    }
    generation += 1
    let requestGeneration = generation
    defer {
      refreshWaiters.removeValue(forKey: requestGeneration)?.forEach { $0.resume() }
    }
    let requestAccess = accessIdentity
    activeAccess = requestAccess
    let requestSource = source
    guard (requestSource == .wallet || connection.isConfigured), let month = selectedMonth else {
      storedState = .idle
      return
    }
    loadingMonth = month
    storedState = .loading
    do {
      let comparison: SpendingComparison
      if requestSource == .wallet, let walletClient, let access = requestAccess.wallet {
        comparison = try await walletClient.fetchComparison(for: month, access: access)
      } else {
        comparison = try await client.fetchComparison(for: month)
      }
      let info = requestSource == .sure ? await client.comparisonMetadata(for: month) : nil
      try Task.checkCancellation()
      guard generation == requestGeneration, accessIdentity == requestAccess else { return }
      guard comparison.month == month else {
        storedState = .failed
        return
      }
      metadata = info
      failure = info?.failure
      storedState = .loaded(comparison)
    } catch {
      guard generation == requestGeneration, accessIdentity == requestAccess else { return }
      failure = DataFailure(error)
      if failure == .cancelled || error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
        storedState = .idle
      } else if (error as? SpendingComparisonServiceError) == .unavailable || failure == .unavailable {
        storedState = .unavailable
      } else if let error = error as? WalletSpendingComparisonBuilder.Failure {
        switch error {
        case .noAccounts: storedState = .noWalletAccounts
        case .multipleCurrencies: storedState = .multipleCurrencies
        case .unknownCurrency: storedState = .unknownCurrency
        case .invalidData: storedState = .failed
        }
      } else {
        // Never expose raw service errors, which could include financial data.
        storedState = .failed
      }
    }
  }

  func invalidate() {
    generation += 1
    storedState = .idle
    metadata = nil
    failure = nil
    loadingMonth = nil
    selectedMonth = nil
    updateMonths()
  }

  private func updateMonths() {
    guard let today = try? LocalDate(now(), in: calendar) else { return }
    let current = SpendingMonth(containing: today)
    let wasCurrent = selectedMonth == months.first
    months = (0..<12).map { current.shifted(by: -$0) }
    if wasCurrent || selectedMonth == nil || !months.contains(selectedMonth!) {
      selectedMonth = current
    }
  }

  enum Source { case sure, wallet }

  struct AccessIdentity: Equatable {
    var previewAllowed: Bool
    var wallet: WalletSpendingAccess?
    var serverConfigured: Bool
    var serverGeneration: Int
  }

  enum State: Equatable {
    case idle, loading, unavailable, failed, noWalletAccounts, multipleCurrencies, unknownCurrency
    case loaded(SpendingComparison)
  }
}
