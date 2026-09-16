import Foundation

/// A server-calculated, acyclic flow. Values are netted within categories by
/// Sure and may differ from the gross monthly income and spending figures.
struct CashFlowGraph: Equatable, Sendable {
  enum Kind: String, Codable, Sendable { case income, expense, cashFlow = "cash_flow", surplus, deficit }
  struct Node: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: Kind
    let value: Decimal
    let percentage: Decimal
    // Opaque user category metadata from Sure; interpreted only by presentation.
    var categoryColor: String? = nil
  }
  struct Link: Equatable, Sendable {
    let source: Int
    let target: Int
    let value: Decimal
    let percentage: Decimal
  }
  let income: DecimalMoney
  let spending: DecimalMoney
  let netSavings: DecimalMoney
  let nodes: [Node]
  let links: [Link]

  init(income: DecimalMoney, spending: DecimalMoney, netSavings: DecimalMoney,
       nodes: [Node], links: [Link]) throws {
    guard income.currency == spending.currency, income.currency == netSavings.currency,
          !income.amount.isNaN, !spending.amount.isNaN, !netSavings.amount.isNaN,
          income.amount >= 0, spending.amount >= 0, income.amount - spending.amount == netSavings.amount,
          Set(nodes.map(\.id)).count == nodes.count,
          nodes.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && !$0.value.isNaN && $0.value > 0
            && !$0.percentage.isNaN && (0...100).contains($0.percentage) }),
          links.allSatisfy({ nodes.indices.contains($0.source) && nodes.indices.contains($0.target)
            && $0.source != $0.target && !$0.value.isNaN && $0.value > 0
            && !$0.percentage.isNaN && (0...100).contains($0.percentage) }) else {
      throw ValidationError.invalidGraph
    }
    var incoming = Array(repeating: Decimal.zero, count: nodes.count)
    var outgoing = incoming
    var indegree = Array(repeating: 0, count: nodes.count)
    var successors = Array(repeating: [Int](), count: nodes.count)
    var neighbors = successors
    for link in links {
      incoming[link.target] += link.value; outgoing[link.source] += link.value
      indegree[link.target] += 1; successors[link.source].append(link.target)
      neighbors[link.source].append(link.target); neighbors[link.target].append(link.source)
    }
    var queue = nodes.indices.filter { indegree[$0] == 0 }
    var cursor = 0
    while cursor < queue.count {
      for target in successors[queue[cursor]] {
        indegree[target] -= 1
        if indegree[target] == 0 { queue.append(target) }
      }
      cursor += 1
    }
    guard queue.count == nodes.count,
          nodes.indices.allSatisfy({ incoming[$0] <= nodes[$0].value && outgoing[$0] <= nodes[$0].value
            && max(incoming[$0], outgoing[$0]) == nodes[$0].value }) else {
      throw ValidationError.invalidGraph
    }
    let centers = nodes.indices.filter { nodes[$0].kind == .cashFlow }
    if nodes.isEmpty {
      guard links.isEmpty, income.amount == 0, spending.amount == 0 else { throw ValidationError.invalidGraph }
    } else {
      guard centers.count == 1, let center = centers.first,
            nodes[center].value == max(income.amount, spending.amount),
            incoming[center] == outgoing[center] else { throw ValidationError.invalidGraph }
      let incomeLinks = links.filter { $0.target == center && nodes[$0.source].kind == .income }
      let expenseLinks = links.filter { $0.source == center && nodes[$0.target].kind == .expense }
      guard incomeLinks.reduce(Decimal.zero, { $0 + $1.value }) == income.amount,
            expenseLinks.reduce(Decimal.zero, { $0 + $1.value }) == spending.amount else {
        throw ValidationError.invalidGraph
      }
      var connected: Set<Int> = [center]
      var pending = [center]
      while let index = pending.popLast() {
        for neighbor in neighbors[index] where connected.insert(neighbor).inserted {
          pending.append(neighbor)
        }
      }
      guard connected.count == nodes.count else { throw ValidationError.invalidGraph }
    }
    self.income = income; self.spending = spending; self.netSavings = netSavings
    self.nodes = nodes; self.links = links
  }

  enum ValidationError: Error { case invalidGraph }
}
