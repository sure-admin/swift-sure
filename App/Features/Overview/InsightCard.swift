import SwiftUI

struct InsightCard: View {
  var insights: [BackendInsight]
  var isLoading: Bool
  var errorMessage: String?
  var notificationManager: any InsightNotificationControlling
  var statusColumnWidth: CGFloat
  var acknowledgingIDs: Set<String>
  var acknowledgmentError: String?
  var acknowledge: (BackendInsight) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var visibleInsights: [BackendInsight] {
    insights.filter { !acknowledgingIDs.contains($0.id) }
  }

  @AppStorage("insightNotificationsEnabled") private var notificationsEnabled = false
  @State private var showingNotificationFailure = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label("AI Insights", systemImage: "sparkles")
          .font(.title3.bold())
        Spacer()
        if !visibleInsights.isEmpty {
          Text("\(visibleInsights.count) NEW")
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(SureTheme.highlight, in: Capsule())
            .foregroundStyle(SureTheme.ink)
            .frame(width: statusColumnWidth)
        }
        if !acknowledgingIDs.isEmpty {
          ProgressView().accessibilityLabel("Dismissing insight")
        }
      }

      if isLoading && insights.isEmpty {
        HStack(spacing: 10) {
          ProgressView()
          Text("Loading insights from Sure…")
            .foregroundStyle(.secondary)
        }
      } else {
        if isLoading {
          HStack(spacing: 10) {
            ProgressView()
            Text("Refreshing insights from Sure…")
              .foregroundStyle(.secondary)
          }
        }
        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        if insights.isEmpty {
          if errorMessage == nil {
            ContentUnavailableView(
              "No new insights",
              systemImage: "checkmark.circle",
              description: Text("Sure has no active insights for this account.")
            )
          }
        } else {
          ForEach(Array(visibleInsights.enumerated()), id: \.element.id) { index, insight in
            if index > 0 { Divider() }
            InsightRow(insight: insight, isAcknowledging: acknowledgingIDs.contains(insight.id)) {
              acknowledge(insight)
            }
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity,
              removal: .move(edge: .leading).combined(with: .opacity)))
          }
        }
      }

      if let acknowledgmentError {
        Text(acknowledgmentError)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("insight-dismissal-error")
      }

      #if os(iOS)
      Toggle("Notify urgent insights", isOn: $notificationsEnabled)
        .onChange(of: notificationsEnabled) { _, enabled in
          Task {
            guard enabled else {
              await notificationManager.disableInsightNotifications()
              return
            }
            let granted = await notificationManager.enableInsightNotifications()
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
    .animation(reduceMotion ? nil : .snappy, value: visibleInsights.map(\.id))
    #if os(iOS)
    .alert("Notifications are off", isPresented: $showingNotificationFailure) {
      Button("OK", role: .cancel) { }
    } message: {
      Text("You can allow notifications for Sure in System Settings.")
    }
    #endif
  }
}
