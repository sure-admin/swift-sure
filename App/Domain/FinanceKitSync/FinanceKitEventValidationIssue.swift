/// A location and contract rule, never a source identifier or financial value.
struct FinanceKitEventValidationIssue: Equatable, Sendable {
  enum Field: String, Sendable {
    case batch
    case accountName = "account.display_name"
    case institutionName = "account.institution_name"
    case accountDescription = "account.account_description"
    case observedAt = "balance.observed_at"
    case transactionDescription = "transaction.transaction_description"
    case originalDescription = "transaction.original_transaction_description"
    case merchantName = "transaction.merchant_name"
    case transactionType = "transaction.transaction_type"
    case status = "transaction.status"
    case transactedAt = "transaction.transacted_at"
    case postedAt = "transaction.posted_at"
    case identity
  }

  enum Rule: Sendable {
    case requiredForBooked, nonblank, textLimit(Int), supportedStatus, notAfterCapture, uniqueIdentity, readablePayload
  }

  var eventIndex: Int?
  var field: Field
  var rule: Rule
}

extension FinanceKitEventValidationIssue.Rule: Equatable { }
