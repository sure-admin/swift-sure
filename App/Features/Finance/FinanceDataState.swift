enum FinanceDataState: Equatable {
  case idle
  case loading
  case loaded
  case needsConnection
  case failed(String)
}
