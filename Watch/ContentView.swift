import SwiftUI

struct ContentView: View {
  var store: WatchInsightsStore

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if store.insights.isEmpty {
            ContentUnavailableView {
              Label("No insights yet", systemImage: "sparkles")
            } description: {
              Text("Open Sure on your iPhone to refresh your insights.")
            }
          } else {
            ForEach(store.insights) { insight in
              insightCard(insight)
            }
          }

          if let lastUpdated = store.lastUpdated {
            Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
              .accessibilityLabel("Insights updated \(lastUpdated.formatted(.relative(presentation: .named)))")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
      }
      .navigationTitle("Insights")
    }
    .task {
      store.start()
    }
  }

  private func insightCard(_ insight: WatchInsight) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(typeLabel(insight.type), systemImage: symbol(insight.type))
        .font(.caption.bold())
        .foregroundStyle(accentColor(insight.priority))

      Text(insight.title)
        .font(.headline)
        .fixedSize(horizontal: false, vertical: true)

      Text(insight.body)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private func typeLabel(_ type: String) -> String {
    type.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private func symbol(_ type: String) -> String {
    switch type.lowercased() {
    case "spending", "spending_anomaly": "creditcard.fill"
    case "income": "arrow.down.circle.fill"
    case "budget": "chart.pie.fill"
    case "cash_flow": "waveform.path.ecg"
    default: "sparkles"
    }
  }

  private func accentColor(_ priority: String) -> Color {
    switch priority.lowercased() {
    case "urgent", "high": .orange
    default: Color(red: 0.376, green: 0.663, blue: 0.267)
    }
  }
}
