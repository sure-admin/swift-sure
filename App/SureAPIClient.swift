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
          let identifier = findString(keys: ["id", "uuid"], in: object) else {
      throw SureAPIError.invalidResponse
    }
    return identifier
  }

  func sendMessage(_ content: String, chatID: String) async throws -> String {
    let data = try await request(
      path: "/api/v1/chats/\(chatID)/messages",
      method: "POST",
      body: ["content": content]
    )
    let object = try JSONSerialization.jsonObject(with: data)
    guard let response = findAssistantContent(in: object) else {
      throw SureAPIError.invalidResponse
    }
    return response
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
      let institution = string(keys: ["institution_name", "institution", "provider_name"], in: account) ?? kind.rawValue
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
      let category = string(keys: ["category_name", "category"], in: transaction) ?? "Uncategorized"
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
    let month = Date.now.formatted(.iso8601.year().month().day())
    let data = try await request(path: "/api/v1/budgets?start_date=\(month)", method: "GET")
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

  private func findAssistantContent(in object: Any) -> String? {
    if let dictionary = object as? [String: Any] {
      if let role = dictionary["role"] as? String,
         role == "assistant",
         let content = dictionary["content"] as? String {
        return content
      }
      if let content = dictionary["content"] as? String { return content }
      if let message = dictionary["message"] as? String { return message }
      for value in dictionary.values {
        if let match = findAssistantContent(in: value) { return match }
      }
    } else if let array = object as? [Any] {
      for value in array.reversed() {
        if let match = findAssistantContent(in: value) { return match }
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

  var errorDescription: String? {
    switch self {
    case .invalidURL: "The Sure server URL is invalid."
    case .invalidResponse: "Sure returned an unexpected response."
    case .unauthorized: "The API key is invalid or lacks access."
    case .server(let code): "Sure returned server error \(code)."
    }
  }
}
