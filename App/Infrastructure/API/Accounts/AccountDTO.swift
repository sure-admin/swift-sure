import Foundation

struct AccountDTO: Decodable, Equatable {
  var id: UUID
  var name: String
  var balance: String
  var balanceCents: Int64
  var cashBalance: String
  var cashBalanceCents: Int64
  var currency: String
  var classification: String
  var accountType: String?
  var subtype: String?
  var status: String
  var institutionName: String?
  var institutionDomain: String?
  var createdAt: Date
  var updatedAt: Date

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    guard container.contains(.accountType) else {
      throw DecodingError.keyNotFound(
        CodingKeys.accountType,
        DecodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "The required nullable account_type field is missing."
        )
      )
    }

    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    balance = try container.decode(String.self, forKey: .balance)
    balanceCents = try container.decode(Int64.self, forKey: .balanceCents)
    cashBalance = try container.decode(String.self, forKey: .cashBalance)
    cashBalanceCents = try container.decode(Int64.self, forKey: .cashBalanceCents)
    currency = try container.decode(String.self, forKey: .currency)
    classification = try container.decode(String.self, forKey: .classification)
    accountType = try container.decodeIfPresent(String.self, forKey: .accountType)
    subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
    status = try container.decode(String.self, forKey: .status)
    institutionName = try container.decodeIfPresent(String.self, forKey: .institutionName)
    institutionDomain = try container.decodeIfPresent(String.self, forKey: .institutionDomain)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
  }

  func accountRecord() throws -> AccountRecord {
    guard let currencyCode = CurrencyCode(currency),
          Self.validStatuses.contains(status) else {
      throw SureAPIError.decoding
    }

    return AccountRecord(
      id: id,
      name: name,
      institutionName: institutionName,
      accountType: accountType,
      classification: classification,
      status: status,
      balance: Money(minorUnits: balanceCents, currency: currencyCode)
    )
  }

  private static let validStatuses: Set<String> = [
    "active",
    "draft",
    "disabled",
    "pending_deletion"
  ]

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case balance
    case balanceCents = "balance_cents"
    case cashBalance = "cash_balance"
    case cashBalanceCents = "cash_balance_cents"
    case currency
    case classification
    case accountType = "account_type"
    case subtype
    case status
    case institutionName = "institution_name"
    case institutionDomain = "institution_domain"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}
