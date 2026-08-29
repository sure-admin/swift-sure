import Foundation

struct TransactionQuery: Equatable {
  var accountFilter: TransactionAccountFilter?
  var categoryIDs: [UUID] = []
  var merchantIDs: [UUID] = []
  var tagIDs: [UUID] = []
  var startDate: LocalDate?
  var endDate: LocalDate?
  var classification: TransactionClassification?
  var search: String?

  func queryItems(page: Int, perPage: Int) -> [URLQueryItem] {
    var items = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "per_page", value: String(perPage))
    ]
    switch accountFilter {
    case .account(let accountID):
      items.append(URLQueryItem(name: "account_id", value: accountID.uuidString.lowercased()))
    case .accounts(let accountIDs):
      items += accountIDs.map {
        URLQueryItem(name: "account_ids[]", value: $0.uuidString.lowercased())
      }
    case nil:
      break
    }
    items += categoryIDs.map { URLQueryItem(name: "category_ids[]", value: $0.uuidString.lowercased()) }
    items += merchantIDs.map { URLQueryItem(name: "merchant_ids[]", value: $0.uuidString.lowercased()) }
    items += tagIDs.map { URLQueryItem(name: "tag_ids[]", value: $0.uuidString.lowercased()) }
    if let startDate {
      items.append(URLQueryItem(name: "start_date", value: startDate.iso8601String))
    }
    if let endDate {
      items.append(URLQueryItem(name: "end_date", value: endDate.iso8601String))
    }
    if let classification {
      items.append(URLQueryItem(name: "type", value: classification.rawValue))
    }
    if let search, !search.isEmpty {
      items.append(URLQueryItem(name: "search", value: search))
    }
    return items
  }
}

extension TransactionQuery {
  init(dateWindow: TransactionDateWindow) {
    startDate = dateWindow.startDate
    endDate = dateWindow.endDate
  }

  init(historyRequest: TransactionHistoryRequest) {
    accountFilter = historyRequest.accountID.map(TransactionAccountFilter.account)
    startDate = historyRequest.dateWindow.startDate
    endDate = historyRequest.dateWindow.endDate
  }
}

enum TransactionAccountFilter: Equatable {
  case account(UUID)
  case accounts([UUID])
}
