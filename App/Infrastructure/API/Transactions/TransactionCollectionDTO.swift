import Foundation

struct TransactionCollectionDTO: Decodable {
  var transactions: [TransactionDTO]
  var pagination: PaginationDTO

  struct TransactionDTO: Decodable {
    var id: UUID
    var date: LocalDate
    var amount: String
    var amountCents: Int64?
    var signedAmountCents: Int64?
    var currency: String
    var name: String
    var notes: String?
    var externalID: String?
    var source: String?
    var userModified: Bool?
    var classification: String
    var account: AccountDTO
    var category: CategoryDTO?
    var merchant: MerchantDTO?
    var tags: [TagDTO]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
      case id
      case date
      case amount
      case amountCents = "amount_cents"
      case signedAmountCents = "signed_amount_cents"
      case currency
      case name
      case notes
      case externalID = "external_id"
      case source
      case userModified = "user_modified"
      case classification
      case account
      case category
      case merchant
      case tags
      case createdAt = "created_at"
      case updatedAt = "updated_at"
    }
  }

  struct AccountDTO: Decodable {
    var id: UUID
    var name: String
    var accountType: String?

    enum CodingKeys: String, CodingKey {
      case id
      case name
      case accountType = "account_type"
    }
  }

  struct CategoryDTO: Decodable {
    var id: UUID
    var name: String
    var color: String
    var icon: String
  }

  struct MerchantDTO: Decodable {
    var id: UUID
    var name: String
  }

  struct TagDTO: Decodable {
    var id: UUID
    var name: String
    var color: String
  }
}
