import Foundation

/// Geometry only: money is converted to floating point after the server has
/// supplied and the domain has validated every node and link amount.
struct SankeyLayout {
  struct Band {
    let source: CGPoint
    let target: CGPoint
    let thickness: CGFloat
    let sourceIndex: Int
    let targetIndex: Int
  }
  let frames: [CGRect]
  let bands: [Band]
  let columnCount: Int

  init(graph: CashFlowGraph, size: CGSize) {
    let count = graph.nodes.count
    guard count > 0 else { frames = []; bands = []; columnCount = 0; return }
    var ranks = Array(repeating: 0, count: count)
    var indegree = Array(repeating: 0, count: count)
    var outgoing = Array(repeating: [Int](), count: count)
    for link in graph.links { indegree[link.target] += 1; outgoing[link.source].append(link.target) }
    var queue = graph.nodes.indices.filter { indegree[$0] == 0 }
    var cursor = 0
    while cursor < queue.count {
      let source = queue[cursor]
      for target in outgoing[source] {
        ranks[target] = max(ranks[target], ranks[source] + 1)
        indegree[target] -= 1
        if indegree[target] == 0 { queue.append(target) }
      }
      cursor += 1
    }
    let columns = (ranks.max() ?? 0) + 1
    columnCount = columns
    let values = graph.nodes.map { CGFloat(NSDecimalNumber(decimal: $0.value).doubleValue) }
    let groups = (0..<columns).map { rank in graph.nodes.indices.filter { ranks[$0] == rank } }
    let height = max(0, size.height - 16)
    let gap = min(14, height * 0.3 / CGFloat(max(1, (groups.map(\.count).max() ?? 1) - 1)))
    let scale = groups.map { group in
      max(0, height - gap * CGFloat(max(0, group.count - 1))) / group.reduce(CGFloat.zero) { $0 + values[$1] }
    }.min() ?? 0
    let width: CGFloat = 12
    var frames = Array(repeating: CGRect.zero, count: count)
    for (rank, group) in groups.enumerated() {
      let used = group.reduce(CGFloat.zero) { $0 + values[$1] * scale } + gap * CGFloat(max(0, group.count - 1))
      var y = (size.height - used) / 2
      for index in group {
        let x = 8 + CGFloat(rank) / CGFloat(max(1, columns - 1)) * max(0, size.width - width - 16)
        frames[index] = CGRect(x: x, y: y, width: width, height: values[index] * scale)
        y += frames[index].height + gap
      }
    }
    self.frames = frames
    var sourceOffsets = Array(repeating: CGFloat.zero, count: count)
    var targetOffsets = sourceOffsets
    bands = graph.links.map { link in
      let thickness = CGFloat(NSDecimalNumber(decimal: link.value).doubleValue) * scale
      let source = frames[link.source], target = frames[link.target]
      let band = Band(source: CGPoint(x: source.maxX, y: source.minY + sourceOffsets[link.source] + thickness / 2),
        target: CGPoint(x: target.minX, y: target.minY + targetOffsets[link.target] + thickness / 2),
        thickness: thickness, sourceIndex: link.source, targetIndex: link.target)
      sourceOffsets[link.source] += thickness; targetOffsets[link.target] += thickness
      return band
    }
  }
}
