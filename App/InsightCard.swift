import SwiftUI

struct InsightCard: View {
  @AppStorage("insightNotificationsEnabled") private var notificationsEnabled = false
  @State private var showingNotificationFailure = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label("AI Insights", systemImage: "sparkles")
          .font(.title3.bold())
        Spacer()
        Text("2 NEW")
          .font(.caption2.bold())
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(SureTheme.accent, in: Capsule())
          .foregroundStyle(SureTheme.ink)
      }

      insight(
        symbol: "creditcard.trianglebadge.exclamationmark",
        title: "A recurring charge increased",
        detail: "Your Acme Internet bill is $10 higher than its six-month average.",
        tint: .orange
      )
      Divider()
      insight(
        symbol: "fork.knife",
        title: "Dining is close to its limit",
        detail: "You have $72 left for dining through the end of August.",
        tint: .purple
      )

      Toggle("Notify me about new insights", isOn: $notificationsEnabled)
        .onChange(of: notificationsEnabled) { _, enabled in
          guard enabled else { return }
          Task {
            let granted = await NotificationManager.shared.enableInsightNotifications()
            if !granted {
              notificationsEnabled = false
              showingNotificationFailure = true
            }
          }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
    .alert("Notifications are off", isPresented: $showingNotificationFailure) {
      Button("OK", role: .cancel) { }
    } message: {
      Text("You can allow notifications for Sure in System Settings.")
    }
  }

  private func insight(symbol: String, title: String, detail: String, tint: Color) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .frame(width: 38, height: 38)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).fontWeight(.semibold)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
