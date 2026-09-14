import SwiftUI

struct CashFlowCard: View {
  let data: FinanceDataStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Cash flow").font(.title3.bold()).accessibilityAddTraits(.isHeader)
      HStack {
        Button("Previous cash flow month", systemImage: "chevron.left") {
          Task { await data.selectPreviousReportingMonth() }
        }
        .labelStyle(.iconOnly)
        .disabled(data.isLoadingReportingPeriod)
        Text(data.reportingPeriodLabel).font(.headline)
        Button("Next cash flow month", systemImage: "chevron.right") {
          Task { await data.selectNextReportingMonth() }
        }
        .labelStyle(.iconOnly)
        .disabled(data.isLoadingReportingPeriod || !data.canSelectNextReportingMonth)
      }
      if data.isLoadingReportingPeriod && data.currentSummary == nil {
        ProgressView("Loading cash flow…")
      } else if let graph = data.currentSummary?.sankey {
        if data.summaryResource.metadata?.source == .cache {
          Label("Downloaded from Sure", systemImage: "internaldrive").font(.caption)
          if let date = data.summaryResource.metadata?.fetchedAt {
            Text(date, format: .dateTime.month().day().hour().minute()).font(.caption)
          }
        }
        if data.summaryResource.failure != nil {
          Label("Couldn’t refresh cash flow. Showing the last downloaded values.", systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.secondary)
        }
        if graph.nodes.isEmpty {
          Text("No cash flow for this month.").foregroundStyle(.secondary)
        } else {
          CashFlowChart(graph: graph)
        }
      } else {
        Label("Cash flow is unavailable", systemImage: "exclamationmark.triangle")
        Button("Retry cash flow", systemImage: "arrow.clockwise") {
          Task { await data.refresh() }
        }
        .buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
  }
}
