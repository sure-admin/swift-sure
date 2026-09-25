import Foundation

enum FinanceKitSourceEvent: Equatable, Sendable {
  case accountUpsert(FinanceKitSourceAccount)
  case accountUnavailable(sourceAccountID: UUID, lineageID: UUID, mappingVersion: Int)
  case balanceUpsert(FinanceKitSourceBalance)
  case transactionUpsert(FinanceKitSourceTransaction)
  case transactionTombstone(FinanceKitSourceTransactionTombstone)
}

extension FinanceKitSourceEvent: Codable {
  private enum Kind: String, Codable {
    case accountUpsert = "account_upsert"
    case accountUnavailable = "account_unavailable"
    case balanceUpsert = "balance_upsert"
    case transactionUpsert = "transaction_upsert"
    case transactionTombstone = "transaction_tombstone"
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case account
    case sourceAccountID = "source_account_id"
    case lineageID = "lineage_id"
    case mappingVersion = "mapping_version"
    case balance
    case transaction
    case tombstone
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .accountUpsert:
      self = .accountUpsert(try container.decode(FinanceKitSourceAccount.self, forKey: .account))
    case .accountUnavailable:
      self = .accountUnavailable(
        sourceAccountID: try container.decode(UUID.self, forKey: .sourceAccountID),
        lineageID: try container.decode(UUID.self, forKey: .lineageID),
        mappingVersion: try container.decode(Int.self, forKey: .mappingVersion)
      )
    case .balanceUpsert:
      self = .balanceUpsert(try container.decode(FinanceKitSourceBalance.self, forKey: .balance))
    case .transactionUpsert:
      self = .transactionUpsert(try container.decode(FinanceKitSourceTransaction.self, forKey: .transaction))
    case .transactionTombstone:
      self = .transactionTombstone(
        try container.decode(FinanceKitSourceTransactionTombstone.self, forKey: .tombstone)
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .accountUpsert(let account):
      try container.encode(Kind.accountUpsert, forKey: .kind)
      try container.encode(account, forKey: .account)
    case .accountUnavailable(let sourceAccountID, let lineageID, let mappingVersion):
      try container.encode(Kind.accountUnavailable, forKey: .kind)
      try container.encode(sourceAccountID, forKey: .sourceAccountID)
      try container.encode(lineageID, forKey: .lineageID)
      try container.encode(mappingVersion, forKey: .mappingVersion)
    case .balanceUpsert(let balance):
      try container.encode(Kind.balanceUpsert, forKey: .kind)
      try container.encode(balance, forKey: .balance)
    case .transactionUpsert(let transaction):
      try container.encode(Kind.transactionUpsert, forKey: .kind)
      try container.encode(transaction, forKey: .transaction)
    case .transactionTombstone(let tombstone):
      try container.encode(Kind.transactionTombstone, forKey: .kind)
      try container.encode(tombstone, forKey: .tombstone)
    }
  }
}
