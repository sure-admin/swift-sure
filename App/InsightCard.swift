import SwiftUI

struct InsightCard: View {
  var insights: [BackendInsight]
  var isLoading: Bool
  var errorMessage: String?

  @AppStorage("insightNotificationsEnabled") private var notificationsEnabled = false
  @State private var showingNotificationFailure = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label("AI Insights", systemImage: "sparkles")
          .font(.title3.bold())
        Spacer()
        if !insights.isEmpty {
          Text("\(insights.count) NEW")
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(SureTheme.highlight, in: Capsule())
            .foregroundStyle(SureTheme.ink)
        }
      }

      if isLoading {
        HStack(spacing: 10) {
          ProgressView()
          Text("Loading insights from Sure…")
            .foregroundStyle(.secondary)
        }
      } else if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else if insights.isEmpty {
        ContentUnavailableView(
          "No new insights",
          systemImage: "checkmark.circle",
          description: Text("Sure has no active insights for this account.")
        )
      } else {
        ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
          if index > 0 { Divider() }
          insightRow(insight)
        }
      }

      #if os(iOS)
      Toggle("Notify me about new insights", isOn: $notificationsEnabled)
        .onChange(of: notificationsEnabled) { _, enabled in
          Task {
            guard enabled else {
              await NotificationManager.shared.disableInsightNotifications()
              return
            }
            let granted = await NotificationManager.shared.enableInsightNotifications()
            if !granted {
              notificationsEnabled = false
              showingNotificationFailure = true
            }
          }
        }
      #endif
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
    #if os(iOS)
    .alert("Notifications are off", isPresented: $showingNotificationFailure) {
      Button("OK", role: .cancel) { }
    } message: {
      Text("You can allow notifications for Sure in System Settings.")
    }
    #endif
  }

  private func insightRow(_ insight: BackendInsight) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol(for: insight.type))
        .frame(width: 38, height: 38)
        .background(tint(for: insight.type).opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
        .foregroundStyle(tint(for: insight.type))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text([insight.typeLabel, insight.periodLabel].compactMap { $0 }.joined(separator: " · "))
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(insight.title)
          .fontWeight(.semibold)
        Text(insight.body)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func symbol(for type: String) -> String {
    switch type {
    case "savings_rate_change": "banknote.fill"
    case "spending_anomaly": "waveform.path.ecg"
    case "cash_flow_warning", "budget_at_risk": "exclamationmark.triangle.fill"
    case "net_worth_milestone": "trophy.fill"
    case "subscription_audit": "arrow.trianglehead.2.clockwise.rotate.90"
    case "idle_cash": "wallet.bifold.fill"
    case "budget_on_track": "checkmark.circle.fill"
    default: "lightbulb.fill"
    }
  }

  private func tint(for type: String) -> Color {
    switch type {
    case "savings_rate_change", "net_worth_milestone", "budget_on_track": .green
    case "spending_anomaly", "cash_flow_warning", "budget_at_risk": .orange
    default: .blue
    }
  }
}
