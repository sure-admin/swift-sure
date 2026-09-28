import Testing
@testable import Sure

@MainActor
@Suite("Diagnostics consent")
struct DiagnosticsStoreTests {
  @Test func disabledNeverStartsOrLogs() {
    let client = DiagnosticsSpy()
    let store = DiagnosticsStore(preferences: MemoryDiagnosticsPreferences(), client: client)
    store.log(.launched)
    store.log(.transactionHistoryLoadFailed(
      source: .sure, scope: .recentActivity, failure: .server
    ))
    #expect(!store.isEnabled)
    #expect(client.calls.isEmpty)
  }

  @Test func consentStartsOnceAndRevocationStopsLogging() {
    let preferences = MemoryDiagnosticsPreferences()
    let client = DiagnosticsSpy()
    let store = DiagnosticsStore(preferences: preferences, client: client)
    store.setEnabled(true)
    store.setEnabled(true)
    store.log(.cleanupFailed(.offlineResponses))
    #expect(preferences.diagnosticsEnabled)
    store.setEnabled(false)
    store.log(.launched)
    store.setEnabled(false)
    #expect(!preferences.diagnosticsEnabled)
    #expect(client.calls == ["start", "cleanup.failed", "stop"])
    store.setEnabled(true)
    #expect(client.calls.last == "start")
  }

  @Test func savedConsentIsRestored() {
    let preferences = MemoryDiagnosticsPreferences()
    preferences.diagnosticsEnabled = true
    let store = DiagnosticsStore(preferences: preferences, client: DiagnosticsSpy())
    #expect(store.isEnabled)
  }

  @Test func missingConfigurationRemainsDisabled() {
    let preferences = MemoryDiagnosticsPreferences()
    preferences.diagnosticsEnabled = true
    let store = DiagnosticsStore(preferences: preferences, client: nil)
    store.setEnabled(true)
    #expect(!store.isEnabled)
    #expect(!store.isAvailable)
  }

  @Test func vocabularyCarriesNoFreeFormValues() {
    #expect(DiagnosticRecord.launched.attributes.isEmpty)
    #expect(DiagnosticRecord.launched.level == .info)
    for operation in DiagnosticOperation.allCases {
      let record = DiagnosticRecord.cleanupFailed(operation)
      #expect(record.attributes == ["operation": operation.rawValue])
      #expect(record.level == .error)
      #expect(DiagnosticRecord.messages.contains(record.message))
    }
    #expect(DiagnosticRecord.messages.contains(DiagnosticRecord.launched.message))
    #expect(DiagnosticRecord.logMessages.count == 2)
    #expect(DiagnosticRecord.messages.count == 3)
    let vocabulary = DiagnosticOperation.allCases.map(\.rawValue) + Array(DiagnosticRecord.messages)
    for term in vocabulary {
      #expect(term == term.lowercased())
      #expect(!term.contains(where: { $0.isWhitespace }))
    }
  }

  @Test func transactionIssueContainsOnlyFixedClassifications() {
    let expectedFailures: [(DataFailure, String)] = [
      (.cancelled, "cancelled"), (.offline, "offline"), (.authentication, "authentication"),
      (.authorization, "authorization"), (.subscription, "subscription"),
      (.unavailable, "unavailable"), (.validation, "validation"),
      (.malformed, "malformed"), (.rateLimited, "rate_limited"), (.server, "server"),
      (.persistence, "persistence"), (.cleanup, "cleanup"), (.unknown, "unknown")
    ]
    for source in DiagnosticTransactionSource.allCases {
      for scope in DiagnosticTransactionScope.allCases {
        for (failure, code) in expectedFailures {
          let record = DiagnosticRecord.transactionHistoryLoadFailed(
            source: source, scope: scope, failure: failure
          )
          #expect(record.message == "transactions.load_failed")
          #expect(record.level == .error)
          #expect(record.attributes == [
            "source": source.rawValue, "scope": scope.rawValue, "failure": code
          ])
          #expect(record.issueFingerprint == [record.message, source.rawValue, scope.rawValue, code])
        }
      }
    }
    #expect(!DiagnosticRecord.logMessages.contains("transactions.load_failed"))
  }

  @Test func cleanupFailuresAreReportedPerStep() async {
    let client = DiagnosticsSpy()
    let lifecycle = ApplicationConnectionLifecycle()
    lifecycle.diagnostics = client
    lifecycle.clearOfflineResponses = { throw DiagnosticsTestError.cleanup }
    lifecycle.resetAppData = { throw DiagnosticsTestError.cleanup }

    await lifecycle.prepareForConnectionChange()
    #expect(client.calls.isEmpty)

    await lifecycle.didCommitConnectionChange()
    #expect(client.calls == ["cleanup.failed"])
    #expect(client.operations == ["offline_responses"])
    #expect(lifecycle.dataCleanupFailure == DataFailure.cleanup)

    lifecycle.didLogOut()
    #expect(client.operations == ["offline_responses", "app_data_reset"])
  }
}

private enum DiagnosticsTestError: Error {
  case cleanup
}

@MainActor
private final class MemoryDiagnosticsPreferences: DiagnosticsPreferences {
  var diagnosticsEnabled = false
}

@MainActor
private final class DiagnosticsSpy: DiagnosticsClient {
  var calls: [String] = []
  var operations: [String] = []

  func start() { calls.append("start") }
  func stop() { calls.append("stop") }

  func log(_ record: DiagnosticRecord) {
    calls.append(record.message)
    if let operation = record.attributes["operation"] { operations.append(operation) }
  }
}
