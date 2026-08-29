enum AccountKind: String, CaseIterable, Identifiable {
  case cash = "Cash"
  case credit = "Credit"
  case investment = "Investment"
  case property = "Property"

  var id: Self { self }

  var symbol: String {
    switch self {
    case .cash: "building.columns.fill"
    case .credit: "creditcard.fill"
    case .investment: "chart.line.uptrend.xyaxis"
    case .property: "house.fill"
    }
  }
}
