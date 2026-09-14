import SwiftUI

struct CashFlowChart: View {
  let graph: CashFlowGraph

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 24) { totals }
        VStack(alignment: .leading, spacing: 12) { totals }
      }
      GeometryReader { geometry in
        let columns = SankeyLayout(graph: graph, size: geometry.size).columnCount
        let width = columns <= 3 ? geometry.size.width : max(geometry.size.width, CGFloat(columns) * 140)
        VStack(alignment: .leading, spacing: 8) {
          ScrollView(.horizontal) {
            diagram(size: CGSize(width: width, height: 300))
              .frame(width: width, height: 300)
          }
          .frame(height: 300)
          if width > geometry.size.width {
            Text("Scroll the chart horizontally to explore the flow.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .frame(height: 340)
      .accessibilityHidden(true)
      DisclosureGroup("Cash flow details") {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(graph.nodes) { node in
            HStack(alignment: .firstTextBaseline) {
              VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                Text(kindLabel(node.kind)).font(.caption).foregroundStyle(.secondary)
              }
              Spacer(minLength: 12)
              Text(money(node.value)).monospacedDigit().multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
          }
        }
        .padding(.top, 12)
      }
      .accessibilityIdentifier("cash-flow-details")
      Text("Calculated by Sure. Refunds are netted within each category; surplus or deficit balances the flow.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var totals: some View {
    metric("Net income", graph.income)
    metric("Net spending", graph.spending)
    metric(graph.netSavings.amount >= 0 ? "Surplus" : "Deficit", graph.netSavings)
  }

  private func metric(_ title: LocalizedStringKey, _ value: DecimalMoney) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(FinanceFormatters.currency(value)).font(.headline).monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }

  private func diagram(size: CGSize) -> some View {
    let layout = SankeyLayout(graph: graph, size: size)
    return ZStack(alignment: .topLeading) {
      Canvas { context, _ in
        for band in layout.bands {
          var path = Path()
          path.move(to: band.source)
          let middle = (band.source.x + band.target.x) / 2
          path.addCurve(to: band.target, control1: CGPoint(x: middle, y: band.source.y),
            control2: CGPoint(x: middle, y: band.target.y))
          context.stroke(path, with: .color(color(graph.nodes[band.targetIndex].kind).opacity(0.2)),
            lineWidth: band.thickness)
        }
        for (index, frame) in layout.frames.enumerated() {
          context.fill(Path(roundedRect: frame, cornerRadius: 3), with: .color(color(graph.nodes[index].kind)))
        }
      }
      ForEach(Array(graph.nodes.enumerated()), id: \.element.id) { index, node in
        let frame = layout.frames[index]
        if frame.height >= 24 {
          let onRight = frame.midX > size.width / 2
          VStack(alignment: onRight ? .trailing : .leading, spacing: 2) {
            Text(node.name).font(.caption.weight(.medium)).lineLimit(1)
            Text(money(node.value)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
          }
          .frame(width: 110, alignment: onRight ? .trailing : .leading)
          .position(x: onRight ? frame.minX - 61 : frame.maxX + 61, y: frame.midY)
        }
      }
    }
  }

  private func money(_ amount: Decimal) -> String {
    FinanceFormatters.currency(DecimalMoney(amount: amount, currency: graph.income.currency))
  }

  private func color(_ kind: CashFlowGraph.Kind) -> Color {
    switch kind {
    case .income, .surplus: SureTheme.accent
    case .expense, .deficit: .orange
    case .cashFlow: .secondary
    }
  }

  private func kindLabel(_ kind: CashFlowGraph.Kind) -> LocalizedStringKey {
    switch kind {
    case .income: "Income"
    case .expense: "Spending"
    case .cashFlow: "Cash flow"
    case .surplus: "Surplus"
    case .deficit: "Deficit"
    }
  }
}
