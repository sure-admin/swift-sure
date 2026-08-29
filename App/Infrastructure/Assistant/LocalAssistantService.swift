import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
struct LocalAssistantService: LocalAssistantResponding {
  var financeData: FinanceDataStore

  func respond(to prompt: String, conversation: [AssistantMessage]) async throws -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      let model = SystemLanguageModel.default
      guard model.isAvailable else {
        throw LocalAssistantError.modelUnavailable
      }

      let session = LanguageModelSession(
        model: model,
        instructions: """
          You are Sure Assistant, a concise and supportive personal finance assistant.
          Use only the supplied financial context for claims specific to the person's money.
          You may still provide clearly framed general financial education when their data is insufficient.
          Say what personal information is missing instead of guessing about it.
          The response is generated privately on this device; never claim that you contacted Sure or any server.
          """
      )
      let response = try await session.respond(
        to: localPrompt(question: prompt, conversation: conversation)
      )
      return response.content
    }
    #endif

    throw LocalAssistantError.unsupportedOperatingSystem
  }

  func localPrompt(question: String, conversation: [AssistantMessage]) -> String {
    """
    Financial context:
    \(financialContext())

    Recent conversation:
    \(conversationContext(conversation))

    Current question:
    \(question)
    """
  }

  private func financialContext() -> String {
    let store = financeData
    var sections = [
      "Reporting period: \(store.reportingPeriodLabel)",
      "Net worth: \(store.netWorth.map(FinanceFormatters.currency) ?? "Unavailable")",
      "Period income: \(FinanceFormatters.currency(store.periodIncome, compact: false, zeroCurrency: store.balanceSheet?.currency))",
      "Period spending: \(FinanceFormatters.currency(store.periodSpending, compact: false, zeroCurrency: store.balanceSheet?.currency))"
    ]

    if !store.accounts.isEmpty {
      let accounts = store.accounts.map { account in
        "- \(account.name) (\(account.kind.rawValue)): \(FinanceFormatters.currency(account.balance))"
      }
      sections.append("Accounts:\n\(accounts.joined(separator: "\n"))")
    }

    if !store.budgets.isEmpty {
      let budgets = store.budgets.map { budget in
        "- \(budget.name): \(FinanceFormatters.currency(budget.spent)) spent of \(FinanceFormatters.currency(budget.limit))"
      }
      sections.append("Budgets:\n\(budgets.joined(separator: "\n"))")
    }

    let transactions = store.reportingPeriodTransactions.prefix(30).map { transaction in
      let direction = transaction.kind == .income ? "income" : "expense"
      return "- \(FinanceFormatters.fullDate(transaction.date)): \(transaction.merchant), \(transaction.category), \(FinanceFormatters.currency(transaction.amount)) \(direction)"
    }
    if !transactions.isEmpty {
      sections.append("Recent transactions:\n\(transactions.joined(separator: "\n"))")
    }

    if store.accounts.isEmpty && store.transactions.isEmpty && store.budgets.isEmpty {
      sections.append("No synced financial records are currently available on this device.")
    }
    return sections.joined(separator: "\n\n")
  }

  private func conversationContext(_ messages: [AssistantMessage]) -> String {
    let recentMessages = messages.suffix(6).map { message in
      let speaker = message.role == .user ? "User" : "Assistant"
      return "\(speaker): \(String(message.content.prefix(1_000)))"
    }
    return recentMessages.isEmpty ? "No previous messages." : recentMessages.joined(separator: "\n")
  }

}

private enum LocalAssistantError: LocalizedError {
  case modelUnavailable
  case unsupportedOperatingSystem

  var errorDescription: String? {
    switch self {
    case .modelUnavailable:
      "The on-device model isn’t available. Check that this device supports Apple Intelligence and that it’s enabled."
    case .unsupportedOperatingSystem:
      "On-device answers require iOS 26 or macOS 26."
    }
  }
}
