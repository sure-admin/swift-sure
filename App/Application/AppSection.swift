enum AppSection: Int, CaseIterable, Hashable {
  case overview
  case assistant
  case accounts
  case budget

  func moving(by offset: Int) -> AppSection {
    let destination = min(max(rawValue + offset, 0), Self.allCases.count - 1)
    return Self(rawValue: destination) ?? self
  }
}
