import Foundation
import Testing
@testable import Sure

@Suite("Cash flow graph contract")
struct CashFlowGraphTests {
  @Test("Server graph survives offline cache encoding with its precision and currency")
  func roundTrip() throws {
    let summary = try summaryFixture()
    let graph = try #require(summary.sankey)
    #expect(graph.spending.amount == Decimal(string: "32.345"))
    #expect(graph.income.currency.rawValue == "USD")
    let restored = try JSONDecoder().decode(CashFlowDTO.self, from: JSONEncoder().encode(CashFlowDTO(summary))).record()
    #expect(restored == summary)
  }

  @Test("Graph amounts retain currencies with zero and three minor-unit digits", arguments: ["JPY", "BHD"])
  func currencies(code: String) throws {
    var dto = try JSONDecoder().decode(CashFlowDTO.self, from: APIFixture.data(named: "cash-flow-success"))
    dto.currency = code
    let graph = try #require(dto.record().sankey)
    #expect(graph.income.currency.rawValue == code)
    #expect(graph.spending.amount == Decimal(string: "32.345"))
  }

  @Test("Merged Sure graph preserves a spending-only deficit path")
  func spendingOnlyDeficit() throws {
    let dto = try JSONDecoder().decode(CashFlowGraphDTO.self,
      from: APIFixture.data(named: "cash-flow-sankey-deficit"))
    let graph = try dto.record(currency: #require(CurrencyCode("USD")))
    #expect(graph.income.amount == 0)
    #expect(graph.spending.amount == 160)
    #expect(graph.netSavings.amount == -160)
    #expect(graph.links.map { graph.nodes[$0.source].kind } == [.cashFlow, .deficit])
    #expect(graph.links.map { graph.nodes[$0.target].kind } == [.expense, .cashFlow])
    #expect(graph.links.allSatisfy { $0.value == 160 })
    let layout = SankeyLayout(graph: graph, size: CGSize(width: 420, height: 300))
    #expect(layout.columnCount == 3)
    #expect(layout.bands.count == 2)
    #expect(layout.bands.allSatisfy { $0.source.x < $0.target.x && $0.thickness > 0 })
  }

  @Test("Old cache records remain readable but do not invent a graph")
  func oldCache() throws {
    var summary = try summaryFixture(); summary.sankey = nil
    let restored = try JSONDecoder().decode(CashFlowDTO.self, from: JSONEncoder().encode(CashFlowDTO(summary))).record()
    #expect(restored.sankey == nil)
    #expect(restored.comparison == summary.comparison)
  }

  @Test("Rejects malformed references, duplicate IDs, cycles, and financial inconsistencies", arguments: 0..<7)
  func malformed(caseIndex: Int) throws {
    var dto = try JSONDecoder().decode(CashFlowDTO.self, from: APIFixture.data(named: "cash-flow-success"))
    var graph = try #require(dto.sankey)
    switch caseIndex {
    case 0: graph.nodes[1].id = graph.nodes[0].id
    case 1: graph.links[0].target = 100
    case 2: graph.nodes[1].value = "NaN"
    case 3: graph.nodes[1].value = "-1"
    case 4: graph.links.append(.init(source: 0, target: 1, value: "1", percentage: "1"))
    case 5: graph.netSavings = "0"
    default: graph.links[0].value = "2000"
    }
    dto.sankey = graph
    #expect(throws: (any Error).self) { try dto.record() }
  }

  @Test("Layout stays within bounds and keeps band allocations within nodes")
  func layout() throws {
    let graph = try #require(summaryFixture().sankey)
    for size in [CGSize(width: 420, height: 300), CGSize(width: 1000, height: 500)] {
      let layout = SankeyLayout(graph: graph, size: size)
      #expect(layout.columnCount == 3)
      for frame in layout.frames {
        #expect(frame.minX >= 0 && frame.minY >= 0)
        #expect(frame.maxX <= size.width && frame.maxY <= size.height)
      }
      for band in layout.bands {
        #expect(band.thickness > 0 && band.thickness.isFinite)
        #expect(band.source.x < band.target.x)
        let source = layout.frames[band.sourceIndex], target = layout.frames[band.targetIndex]
        #expect(band.source.y - band.thickness / 2 >= source.minY - 0.0001)
        #expect(band.source.y + band.thickness / 2 <= source.maxY + 0.0001)
        #expect(band.target.y + band.thickness / 2 <= target.maxY + 0.0001)
      }
    }
  }
}
