import Foundation

enum TransactionHistoryScope: Equatable, Sendable {
  case account(id: UUID, name: String)
  case recentActivity

  var accountID: UUID? {
    switch self {
    case .account(let id, _): id
    case .recentActivity: nil
    }
  }

  var dayCount: Int {
    switch self {
    case .account: 31
    case .recentActivity: 7
    }
  }

  var navigationTitle: String {
    switch self {
    case .account(_, let name): name
    case .recentActivity: "Recent activity"
    }
  }

  var periodLabel: String {
    "Last \(dayCount) days"
  }

  var emptyTitle: String {
    switch self {
    case .account: "No transactions"
    case .recentActivity: "No recent activity"
    }
  }

  var emptyDescription: String {
    switch self {
    case .account(_, let name):
      "No transactions were found for \(name) in the last 31 days."
    case .recentActivity:
      "No transactions were found in the last 7 days."
    }
  }
}
