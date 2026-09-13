import Foundation

struct DownloadedTransactionWindow {
  var request: TransactionHistoryRequest
  var transactions: [FinanceTransaction]
  var metadata: ReadMetadata
}
