import SwiftUI

/// Cash-flow Sankey artwork: income sources → cash flow → categories and
/// surplus. `progress` sweeps the bands in left to right, then shows labels.
struct FirstRunSankey: View, Animatable {
  var showcase: FirstRunShowcase
  var progress: Double
  var fontSize: CGFloat = 10

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  private static let nodeWidth: CGFloat = 6

  var body: some View {
    Canvas { context, size in
      let layout = Layout(showcase: showcase, size: size, gap: fontSize < 12 ? 6 : 8)
      let reveal = min(max(progress, 0), 1)

      var bands = context
      bands.clip(to: Path(CGRect(x: 0, y: -20, width: size.width * reveal, height: size.height + 40)))
      for band in layout.bands {
        bands.fill(band.path, with: .color(FirstRunPalette.color(band.tint).opacity(0.26)))
      }

      let nodeScale = min(reveal * 2.5, 1)
      for node in layout.sources + layout.targets {
        context.fill(
          Path(roundedRect: node.rect.scaledVertically(nodeScale), cornerRadius: 2),
          with: .color(FirstRunPalette.color(node.tint))
        )
      }
      context.fill(Path(roundedRect: layout.center.scaledVertically(nodeScale), cornerRadius: 2), with: .color(FirstRunPalette.chartLabel))

      var labels = context
      labels.opacity = max(0, (reveal - 0.7) / 0.3)
      let nameFont = Font.system(size: fontSize, weight: .medium)
      let figure = Font.system(size: fontSize).monospacedDigit()
      for node in layout.sources {
        labels.draw(Text(node.name).font(nameFont).foregroundStyle(FirstRunPalette.chartInk),
          at: CGPoint(x: 14, y: node.rect.midY - fontSize * 0.6), anchor: .leading)
        labels.draw(Text(money(node.amount)).font(figure).foregroundStyle(FirstRunPalette.chartLabel),
          at: CGPoint(x: 14, y: node.rect.midY + fontSize * 0.6), anchor: .leading)
      }
      labels.draw(Text("Cash flow").font(.system(size: fontSize)).foregroundStyle(FirstRunPalette.chartLabel),
        at: CGPoint(x: layout.center.midX, y: layout.center.minY - 8), anchor: .bottom)
      for node in layout.targets {
        let surplus = node.tint == .surplus
        let ink = surplus ? FirstRunPalette.green : FirstRunPalette.chartInk
        labels.draw(Text(node.name).font(.system(size: fontSize, weight: surplus ? .semibold : .medium)).foregroundStyle(ink),
          at: CGPoint(x: node.rect.maxX + 6, y: node.rect.midY), anchor: .leading)
        labels.draw(Text(money(node.amount)).font(figure).foregroundStyle(surplus ? FirstRunPalette.green : FirstRunPalette.chartLabel),
          at: CGPoint(x: size.width, y: node.rect.midY), anchor: .trailing)
      }
    }
    .accessibilityHidden(true)
  }

  private func money(_ amount: Decimal) -> String {
    FinanceFormatters.wholeCurrency(DecimalMoney(amount: amount, currency: showcase.currency))
  }

  private struct Node {
    var name: String
    var amount: Decimal
    var tint: FirstRunShowcase.Tint
    var rect: CGRect
  }

  private struct Band {
    var path: Path
    var tint: FirstRunShowcase.Tint
  }

  // Geometry only; amounts are converted to Double solely to size the bands.
  private struct Layout {
    var sources: [Node] = []
    var targets: [Node] = []
    var center: CGRect = .zero
    var bands: [Band] = []

    init(showcase: FirstRunShowcase, size: CGSize, gap: CGFloat) {
      let width = FirstRunSankey.nodeWidth
      let value = { (amount: Decimal) in CGFloat(NSDecimalNumber(decimal: amount).doubleValue) }
      let total = showcase.incomes.reduce(CGFloat(0)) { $0 + value($1.amount) }
      guard total > 0 else { return }
      let centerX = (size.width * 0.34).rounded()
      let targetX = (size.width * 0.58).rounded()
      let scale = (size.height - gap * CGFloat(max(showcase.outflows.count - 1, 0))) / total

      var y = (size.height - (total * scale + gap * CGFloat(showcase.incomes.count - 1))) / 2
      for flow in showcase.incomes {
        let height = value(flow.amount) * scale
        sources.append(Node(name: flow.name, amount: flow.amount, tint: flow.tint, rect: CGRect(x: 0, y: y, width: width, height: height)))
        y += height + gap
      }
      center = CGRect(x: centerX, y: (size.height - total * scale) / 2, width: width, height: total * scale)
      y = 0
      for flow in showcase.outflows {
        let height = value(flow.amount) * scale
        targets.append(Node(name: flow.name, amount: flow.amount, tint: flow.tint, rect: CGRect(x: targetX, y: y, width: width, height: height)))
        y += height + gap
      }

      var inflow = center.minY
      for node in sources {
        bands.append(Band(path: Self.band(from: CGPoint(x: width, y: node.rect.minY), to: CGPoint(x: centerX, y: inflow), height: node.rect.height), tint: node.tint))
        inflow += node.rect.height
      }
      var outflow = center.minY
      for node in targets {
        bands.append(Band(path: Self.band(from: CGPoint(x: centerX + width, y: outflow), to: CGPoint(x: targetX, y: node.rect.minY), height: node.rect.height), tint: node.tint))
        outflow += node.rect.height
      }
    }

    private static func band(from start: CGPoint, to end: CGPoint, height: CGFloat) -> Path {
      let mid = (start.x + end.x) / 2
      var path = Path()
      path.move(to: start)
      path.addCurve(to: end, control1: CGPoint(x: mid, y: start.y), control2: CGPoint(x: mid, y: end.y))
      path.addLine(to: CGPoint(x: end.x, y: end.y + height))
      path.addCurve(to: CGPoint(x: start.x, y: start.y + height),
        control1: CGPoint(x: mid, y: end.y + height), control2: CGPoint(x: mid, y: start.y + height))
      path.closeSubpath()
      return path
    }
  }
}

private extension CGRect {
  func scaledVertically(_ factor: CGFloat) -> CGRect {
    let height = self.height * factor
    return CGRect(x: minX, y: midY - height / 2, width: width, height: height)
  }
}
