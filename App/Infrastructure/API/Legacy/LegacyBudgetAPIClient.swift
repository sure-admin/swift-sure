import Foundation

// Intentionally quarantined until the budget contract is migrated. The pinned
// category list omits actual spending, so preserving the current UI requires a
// separate product decision about detail hydration.
struct LegacyBudgetAPIClient {
  var transport: SureAPITransport

  func fetchBudgetCategories() async throws -> [BudgetCategory] {
    let data = try await request(pathComponents: ["api", "v1", "budgets"])
    let object = try JSONSerialization.jsonObject(with: data)
    let budgetObjects = findDictionaries(named: "budgets", in: object)
    guard let budget = budgetObjects.first,
          let budgetID = string(keys: ["id", "uuid"], in: budget) else { return [] }
    let categoriesData = try await request(
      pathComponents: ["api", "v1", "budgets", budgetID, "categories"]
    )
    let categoriesObject = try JSONSerialization.jsonObject(with: categoriesData)
    return findDictionaries(named: "budget_categories", in: categoriesObject).compactMap { category in
      guard let name = string(keys: ["name", "category_name"], in: category),
            let spent = money(
              keys: ["actual_spending", "spent", "actual"],
              centsKeys: ["actual_spending_cents"],
              in: category
            ),
            let limit = money(
              keys: ["budgeted_spending", "limit", "budgeted"],
              centsKeys: ["budgeted_spending_cents"],
              in: category
            ) else {
        return nil
      }
      return BudgetCategory(
        id: string(keys: ["id", "uuid"], in: category) ?? UUID().uuidString,
        name: name,
        symbol: FinancePresentationMapping.symbol(for: name, kind: .expense),
        spent: abs(spent),
        limit: abs(limit)
      )
    }
  }

  private func request(pathComponents: [String]) async throws -> Data {
    try await transport.send(
      APIRequest<Data>(method: .get, pathComponents: pathComponents)
    )
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
}
