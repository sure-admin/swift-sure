import Foundation

struct FinanceDataSnapshotCodec {
  private var encoder: JSONEncoder
  private var decoder: JSONDecoder

  init(
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.encoder = encoder
    self.decoder = decoder
  }

  func encode(_ snapshot: FinanceDataSnapshot) throws -> Data {
    do {
      return try encoder.encode(SnapshotPayload(snapshot))
    } catch {
      throw FinanceDataSnapshotCodingError.malformedPayload
    }
  }

  func decode(_ data: Data) throws -> FinanceDataSnapshot {
    do {
      return try decoder.decode(SnapshotPayload.self, from: data).snapshot()
    } catch {
      throw FinanceDataSnapshotCodingError.malformedPayload
    }
  }
}

enum FinanceDataSnapshotCodingError: Error, Equatable {
  case malformedPayload
}

private struct SnapshotPayload: Codable {
  var serverURL: URL
  var connectionIdentity: String
  var balanceSheet: BalanceSheetPayload?
  var accounts: [AccountPayload]
  var transactions: [TransactionPayload]
  var budgets: [BudgetPayload]
  var insights: [InsightPayload]
  var lastUpdated: Date?

  init(_ snapshot: FinanceDataSnapshot) {
    serverURL = snapshot.serverURL
    connectionIdentity = snapshot.connectionIdentity
    balanceSheet = snapshot.balanceSheet.map(BalanceSheetPayload.init)
    accounts = snapshot.accounts.map(AccountPayload.init)
    transactions = snapshot.transactions.map(TransactionPayload.init)
    budgets = snapshot.budgets.map(BudgetPayload.init)
    insights = snapshot.insights.map(InsightPayload.init)
    lastUpdated = snapshot.lastUpdated
  }

  func snapshot() throws -> FinanceDataSnapshot {
    FinanceDataSnapshot(
      serverURL: serverURL,
      connectionIdentity: connectionIdentity,
      balanceSheet: try balanceSheet?.record(),
      accounts: try accounts.map { try $0.account() },
      transactions: try transactions.map { try $0.transaction() },
      budgets: try budgets.map { try $0.budget() },
      insights: insights.map { $0.insight() },
      lastUpdated: lastUpdated
    )
  }
}

private struct BalanceSheetPayload: Codable {
  var currency: String
  var netWorth: DecimalMoneyPayload
  var assets: DecimalMoneyPayload
  var liabilities: DecimalMoneyPayload

  init(_ balanceSheet: BalanceSheetRecord) {
    currency = balanceSheet.currency.rawValue
    netWorth = DecimalMoneyPayload(balanceSheet.netWorth)
    assets = DecimalMoneyPayload(balanceSheet.assets)
    liabilities = DecimalMoneyPayload(balanceSheet.liabilities)
  }

  func record() throws -> BalanceSheetRecord {
    guard let currency = CurrencyCode(currency) else {
      throw FinanceDataSnapshotCodingError.malformedPayload
    }
    let netWorth = try netWorth.money()
    let assets = try assets.money()
    let liabilities = try liabilities.money()
    guard netWorth.currency == currency,
          assets.currency == currency,
          liabilities.currency == currency else {
      throw FinanceDataSnapshotCodingError.malformedPayload
    }
    return BalanceSheetRecord(
      currency: currency,
      netWorth: netWorth,
      assets: assets,
      liabilities: liabilities
    )
  }
}

private struct DecimalMoneyPayload: Codable {
  var amount: String
  var currency: String

  init(_ money: DecimalMoney) {
    amount = NSDecimalNumber(decimal: money.amount).stringValue
    currency = money.currency.rawValue
  }

  func money() throws -> DecimalMoney {
    guard let amount = Decimal(
      string: amount,
      locale: Locale(identifier: "en_US_POSIX")
    ),
    let currency = CurrencyCode(currency) else {
      throw FinanceDataSnapshotCodingError.malformedPayload
    }
    return DecimalMoney(amount: amount, currency: currency)
  }
}

private struct MoneyPayload: Codable {
  var minorUnits: Int64
  var currency: String

  init(_ money: Money) {
    minorUnits = money.minorUnits
    currency = money.currency.rawValue
  }

  func money() throws -> Money {
    guard let currency = CurrencyCode(currency) else {
      throw FinanceDataSnapshotCodingError.malformedPayload
    }
    return Money(minorUnits: minorUnits, currency: currency)
  }
}

private struct AccountPayload: Codable {
  var id: UUID
  var name: String
  var institution: String
  var kind: String
  var balance: MoneyPayload
  var tintName: String

  init(_ account: FinanceAccount) {
    id = account.id
    name = account.name
    institution = account.institution
    kind = account.kind.rawValue
    balance = MoneyPayload(account.balance)
    tintName = account.tintName
  }

  func account() throws -> FinanceAccount {
    guard let kind = AccountKind(rawValue: kind) else {
      throw FinanceDataSnapshotCodingError.malformedPayload
    }
    return FinanceAccount(
      id: id,
      name: name,
      institution: institution,
      kind: kind,
      balance: try balance.money(),
      tintName: tintName
    )
  }
}

private struct TransactionPayload: Codable {
  var id: UUID
  var merchant: String
  var category: String
  var symbol: String
  var date: LocalDate
  var amount: MoneyPayload
  var kind: String
  var accountID: UUID

  init(_ transaction: FinanceTransaction) {
    id = transaction.id
    merchant = transaction.merchant
    category = transaction.category
    symbol = transaction.symbol
    date = transaction.date
    amount = MoneyPayload(transaction.amount)
    kind = switch transaction.kind {
    case .income: "income"
    case .expense: "expense"
    }
    accountID = transaction.accountID
  }

  func transaction() throws -> FinanceTransaction {
    let transactionKind: TransactionKind
    switch kind {
    case "income": transactionKind = .income
    case "expense": transactionKind = .expense
    default: throw FinanceDataSnapshotCodingError.malformedPayload
    }
    return FinanceTransaction(
      id: id,
      merchant: merchant,
      category: category,
      symbol: symbol,
      date: date,
      amount: try amount.money(),
      kind: transactionKind,
      accountID: accountID
    )
  }
}

private struct BudgetPayload: Codable {
  var id: UUID
  var name: String
  var symbol: String
  var spent: MoneyPayload
  var limit: MoneyPayload

  init(_ budget: BudgetCategory) {
    id = budget.id
    name = budget.name
    symbol = budget.symbol
    spent = MoneyPayload(budget.spent)
    limit = MoneyPayload(budget.limit)
  }

  func budget() throws -> BudgetCategory {
    let spent = try spent.money()
    let limit = try limit.money()
    guard spent.currency == limit.currency else {
      throw FinanceDataSnapshotCodingError.malformedPayload
    }
    return BudgetCategory(
      id: id,
      name: name,
      symbol: symbol,
      spent: spent,
      limit: limit
    )
  }
}

private struct InsightPayload: Codable {
  var id: String
  var type: String
  var title: String
  var body: String
  var priority: String
  var status: String
  var generatedAt: Date?

  init(_ insight: BackendInsight) {
    id = insight.id
    type = insight.type
    title = insight.title
    body = insight.body
    priority = insight.priority
    status = insight.status
    generatedAt = insight.generatedAt
  }

  func insight() -> BackendInsight {
    BackendInsight(
      id: id,
      type: type,
      title: title,
      body: body,
      priority: priority,
      status: status,
      generatedAt: generatedAt
    )
  }
}
