import SwiftUI

struct InsightCard: View {
  var transactions: [FinanceTransaction]
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

      if let topCategory {
        insight(
          symbol: "chart.bar.fill",
          title: "Your top spending category is \(topCategory.name)",
          detail: "You’ve spent \(topCategory.total.formatted(FinanceFormatters.currency)) there in the loaded period.",
          tint: .orange
        )
      }
      if let largestExpense {
        Divider()
        insight(
          symbol: "creditcard.trianglebadge.exclamationmark",
          title: "Largest recent expense",
          detail: "\(largestExpense.merchant) was \(largestExpense.amount.formatted(FinanceFormatters.currency)).",
          tint: .purple
        )
      }

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

  private var largestExpense: FinanceTransaction? {
    transactions.filter { $0.kind == .expense }.max { $0.amount < $1.amount }
  }

  private var topCategory: (name: String, total: Double)? {
    let expenses = transactions.filter { $0.kind == .expense }
    let totals = Dictionary(grouping: expenses, by: \.category)
      .mapValues { $0.reduce(0) { $0 + $1.amount } }
    return totals.max { $0.value < $1.value }.map { ($0.key, $0.value) }
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
