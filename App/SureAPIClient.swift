import Foundation

struct SureAPIClient {
  var connection: SureConnection

  func request(path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
    guard let baseURL = URL(string: connection.serverURL),
          let url = URL(string: path, relativeTo: baseURL) else {
      throw SureAPIError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(connection.apiKey, forHTTPHeaderField: "X-Api-Key")
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw SureAPIError.invalidResponse
    }
    guard 200..<300 ~= httpResponse.statusCode else {
      if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
        throw SureAPIError.unauthorized
      }
      throw SureAPIError.server(httpResponse.statusCode)
    }
    return data
  }

  func createChat() async throws -> String {
    let data = try await request(
      path: "/api/v1/chats",
      method: "POST",
      body: ["title": "Sure for Apple"]
    )
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let identifier = object["id"] as? String else {
      throw SureAPIError.invalidResponse
    }
    return identifier
  }

  func sendMessage(_ content: String, chatID: String) async throws -> String {
    let existingReplies = try await fetchAssistantReplies(chatID: chatID)
    let existingReplyIDs = Set(existingReplies.map(\.id))

    let submissionData = try await request(
      path: "/api/v1/chats/\(chatID)/messages",
      method: "POST",
      body: ["content": content]
    )
    if let submission = try JSONSerialization.jsonObject(with: submissionData) as? [String: Any],
       submission["ai_response_status"] as? String == "failed" {
      let message = submission["ai_response_message"] as? String ?? "Sure could not generate a response."
      throw SureAPIError.backend(message)
    }

    for attempt in 0..<45 {
      if attempt > 0 {
        try await Task.sleep(for: .seconds(1))
      }
      let replies = try await fetchAssistantReplies(chatID: chatID)
      if let reply = replies.last(where: { reply in
        !existingReplyIDs.contains(reply.id) && !reply.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) {
        return reply.content
      }
    }
    throw SureAPIError.responseTimeout
  }

  private func fetchAssistantReplies(chatID: String) async throws -> [RemoteAssistantReply] {
    let data = try await request(path: "/api/v1/chats/\(chatID)", method: "GET")
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SureAPIError.invalidResponse
    }
    if let backendError = object["error"] as? String, !backendError.isEmpty {
      throw SureAPIError.backend(backendError)
    }
    guard let messages = object["messages"] as? [[String: Any]] else {
      throw SureAPIError.invalidResponse
    }
    return messages.compactMap { message in
      guard message["role"] as? String == "assistant",
            let id = message["id"] as? String,
            let content = message["content"] as? String else { return nil }
      return RemoteAssistantReply(id: id, content: content)
    }
  }

  func fetchAccounts() async throws -> [FinanceAccount] {
    let data = try await request(path: "/api/v1/accounts", method: "GET")
    let object = try JSONSerialization.jsonObject(with: data)
    return findDictionaries(named: "accounts", in: object).compactMap { account in
      guard let name = string(keys: ["name"], in: account),
            let balance = money(keys: ["balance", "current_balance", "balance_amount"], centsKeys: ["balance_cents"], in: account) else {
        return nil
      }
      let identifier = string(keys: ["id", "uuid"], in: account) ?? UUID().uuidString
      let classification = string(keys: ["classification", "account_type", "type"], in: account)?.lowercased() ?? ""
      let signedBalance = classification.contains("liabil") || classification.contains("credit") ? -abs(balance) : balance
      let kind: AccountKind
      if classification.contains("invest") { kind = .investment }
      else if classification.contains("credit") || classification.contains("liabil") { kind = .credit }
      else if classification.contains("property") || classification.contains("real_estate") { kind = .property }
      else { kind = .cash }
      let institution = string(keys: ["institution_name", "provider_name"], in: account)
        ?? nestedString(parent: "institution", keys: ["name"], in: account)
        ?? kind.rawValue
      let colors = ["blue", "teal", "purple", "orange"]
      return FinanceAccount(
        id: identifier,
        name: name,
        institution: institution,
        kind: kind,
        balance: signedBalance,
        change: 0,
        tintName: colors[abs(identifier.hashValue) % colors.count]
      )
    }
  }

  func fetchTransactions() async throws -> [FinanceTransaction] {
    let data = try await request(path: "/api/v1/transactions?per_page=100", method: "GET")
    let object = try JSONSerialization.jsonObject(with: data)
    return findDictionaries(named: "transactions", in: object).compactMap { transaction in
      guard let name = string(keys: ["name", "merchant_name"], in: transaction),
            let amount = money(keys: ["amount", "signed_amount"], centsKeys: ["amount_cents", "signed_amount_cents"], in: transaction) else {
        return nil
      }
      let identifier = string(keys: ["id", "uuid"], in: transaction) ?? UUID().uuidString
      let classification = string(keys: ["classification", "nature", "kind"], in: transaction)?.lowercased() ?? "expense"
      let kind: TransactionKind = classification.contains("income") ? .income : .expense
      let category = string(keys: ["category_name"], in: transaction)
        ?? nestedString(parent: "category", keys: ["name"], in: transaction)
        ?? "Uncategorized"
      let date = dateValue(keys: ["date", "transacted_at", "created_at"], in: transaction) ?? .now
      return FinanceTransaction(
        id: identifier,
        merchant: name,
        category: category,
        symbol: symbol(for: category, kind: kind),
        date: date,
        amount: abs(amount),
        kind: kind
      )
    }
    .sorted { $0.date > $1.date }
  }

  func fetchBudgetCategories() async throws -> [BudgetCategory] {
    let data = try await request(path: "/api/v1/budgets", method: "GET")
    let object = try JSONSerialization.jsonObject(with: data)
    let budgetObjects = findDictionaries(named: "budgets", in: object)
    guard let budget = budgetObjects.first,
          let budgetID = string(keys: ["id", "uuid"], in: budget) else { return [] }
    let categoriesData = try await request(path: "/api/v1/budgets/\(budgetID)/categories", method: "GET")
    let categoriesObject = try JSONSerialization.jsonObject(with: categoriesData)
    return findDictionaries(named: "budget_categories", in: categoriesObject).compactMap { category in
      guard let name = string(keys: ["name", "category_name"], in: category),
            let spent = money(keys: ["actual_spending", "spent", "actual"], centsKeys: ["actual_spending_cents"], in: category),
            let limit = money(keys: ["budgeted_spending", "limit", "budgeted"], centsKeys: ["budgeted_spending_cents"], in: category) else {
        return nil
      }
      return BudgetCategory(
        id: string(keys: ["id", "uuid"], in: category) ?? UUID().uuidString,
        name: name,
        symbol: symbol(for: name, kind: .expense),
        spent: abs(spent),
        limit: abs(limit)
      )
    }
  }

  private func findString(keys: [String], in object: Any) -> String? {
    if let dictionary = object as? [String: Any] {
      for key in keys {
        if let value = dictionary[key] as? String { return value }
        if let value = dictionary[key] as? NSNumber { return value.stringValue }
      }
      for value in dictionary.values {
        if let match = findString(keys: keys, in: value) { return match }
      }
    } else if let array = object as? [Any] {
      for value in array {
        if let match = findString(keys: keys, in: value) { return match }
      }
    }
    return nil
  }

  private func findDictionaries(named key: String, in object: Any) -> [[String: Any]] {
    if let dictionary = object as? [String: Any] {
      if let matches = dictionary[key] as? [[String: Any]] { return matches }
      for value in dictionary.values {
        let matches = findDictionaries(named: key, in: value)
        if !matches.isEmpty { return matches }
      }
    } else if let array = object as? [Any] {
      for value in array {
        let matches = findDictionaries(named: key, in: value)
        if !matches.isEmpty { return matches }
      }
    }
    return []
  }

  private func string(keys: [String], in object: Any) -> String? {
    if let dictionary = object as? [String: Any] {
      for key in keys {
        if let value = dictionary[key] as? String { return value }
        if let value = dictionary[key] as? NSNumber { return value.stringValue }
      }
      for value in dictionary.values {
        if let match = string(keys: keys, in: value) { return match }
      }
    }
    return nil
  }

  private func money(keys: [String], centsKeys: [String], in object: Any) -> Double? {
    guard let dictionary = object as? [String: Any] else { return nil }
    for key in centsKeys {
      if let value = dictionary[key] as? NSNumber { return value.doubleValue / 100 }
      if let text = dictionary[key] as? String, let value = Double(text) { return value / 100 }
    }
    for key in keys {
      if let value = dictionary[key] as? NSNumber { return value.doubleValue }
      if let text = dictionary[key] as? String {
        let cleaned = text.filter { "0123456789.-".contains($0) }
        if let value = Double(cleaned) { return value }
      }
    }
    return nil
  }

  private func nestedString(parent: String, keys: [String], in object: Any) -> String? {
    guard let dictionary = object as? [String: Any], let nested = dictionary[parent] else { return nil }
    return string(keys: keys, in: nested)
  }

  private func dateValue(keys: [String], in object: Any) -> Date? {
    guard let text = string(keys: keys, in: object) else { return nil }
    if let date = ISO8601DateFormatter().date(from: text) { return date }
    return try? Date(text, strategy: .dateTime.year().month().day())
  }

  private func symbol(for category: String, kind: TransactionKind) -> String {
    if kind == .income { return "arrow.down.left.circle.fill" }
    let lowered = category.lowercased()
    if lowered.contains("food") || lowered.contains("grocer") { return "cart.fill" }
    if lowered.contains("dining") || lowered.contains("restaurant") { return "fork.knife" }
    if lowered.contains("transport") || lowered.contains("auto") { return "car.fill" }
    if lowered.contains("util") { return "bolt.fill" }
    if lowered.contains("shop") { return "bag.fill" }
    if lowered.contains("invest") { return "chart.line.uptrend.xyaxis" }
    return "creditcard.fill"
  }
}

enum SureAPIError: LocalizedError {
  case invalidURL
  case invalidResponse
  case unauthorized
  case server(Int)
  case backend(String)
  case responseTimeout

  var errorDescription: String? {
    switch self {
    case .invalidURL: "The Sure server URL is invalid."
    case .invalidResponse: "Sure returned an unexpected response."
    case .unauthorized: "The API key is invalid or lacks access."
    case .server(let code): "Sure returned server error \(code)."
    case .backend(let message): message
    case .responseTimeout: "Sure is still working on that response. Try again in a moment."
    }
  }
}

private struct RemoteAssistantReply {
  var id: String
  var content: String
}
