import Foundation

struct FinanceKitSourceTransaction: Codable, Equatable, Sendable {
  var sourceID: UUID
  var sourceAccountID: UUID
  var lineageID: UUID
  var mappingVersion: Int
  var amount: FinanceKitSourceMoney
  var foreignAmount: FinanceKitSourceMoney?
  var foreignExchangeRate: String?
  var transactionDescription: String
  var originalTransactionDescription: String
  var merchantName: String?
  var merchantCategoryCode: Int16?
  var transactionType: String
  var status: String
  var transactedAt: Date
  var postedAt: Date?

  private enum CodingKeys: String, CodingKey {
    case sourceID = "source_id"
    case sourceAccountID = "source_account_id"
    case lineageID = "lineage_id"
    case mappingVersion = "mapping_version"
    case amount
    case foreignAmount = "foreign_amount"
    case foreignExchangeRate = "foreign_exchange_rate"
    case transactionDescription = "transaction_description"
    case originalTransactionDescription = "original_transaction_description"
    case merchantName = "merchant_name"
    case merchantCategoryCode = "merchant_category_code"
    case transactionType = "transaction_type"
    case status
    case transactedAt = "transacted_at"
    case postedAt = "posted_at"
  }
}
