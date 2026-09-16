import Foundation

struct CashFlowGraphDTO: Codable {
  var basis: String
  var income: String
  var spending: String
  var netSavings: String
  var nodes: [Node]
  var links: [Link]
  enum CodingKeys: String, CodingKey { case basis, income, spending, nodes, links; case netSavings = "net_savings" }
  struct Node: Codable {
    var id: String
    var name: String
    var kind: CashFlowGraph.Kind
    var value: String
    var percentage: String
    var color: String? = nil
  }
  struct Link: Codable {
    var source: Int
    var target: Int
    var value: String
    var percentage: String
  }

  func record(currency: CurrencyCode) throws -> CashFlowGraph {
    guard basis == "net_by_category" else { throw SureAPIError.decoding }
    return try CashFlowGraph(
      income: .init(amount: CashFlowDTO.decimal(income), currency: currency),
      spending: .init(amount: CashFlowDTO.decimal(spending), currency: currency),
      netSavings: .init(amount: CashFlowDTO.decimal(netSavings), currency: currency),
      nodes: nodes.map { try .init(id: $0.id, name: $0.name, kind: $0.kind,
        value: CashFlowDTO.decimal($0.value), percentage: CashFlowDTO.decimal($0.percentage), categoryColor: $0.color) },
      links: links.map { try .init(source: $0.source, target: $0.target,
        value: CashFlowDTO.decimal($0.value), percentage: CashFlowDTO.decimal($0.percentage)) })
  }

  init(_ record: CashFlowGraph) {
    basis = "net_by_category"
    income = CashFlowDTO.string(record.income.amount)
    spending = CashFlowDTO.string(record.spending.amount)
    netSavings = CashFlowDTO.string(record.netSavings.amount)
    nodes = record.nodes.map { .init(id: $0.id, name: $0.name, kind: $0.kind,
      value: CashFlowDTO.string($0.value), percentage: CashFlowDTO.string($0.percentage), color: $0.categoryColor) }
    links = record.links.map { .init(source: $0.source, target: $0.target,
      value: CashFlowDTO.string($0.value), percentage: CashFlowDTO.string($0.percentage)) }
  }
}
