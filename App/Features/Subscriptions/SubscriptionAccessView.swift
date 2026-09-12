import SwiftUI

struct SubscriptionAccessView: View {
  var access: SubscriptionAccessStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Sure Sync", systemImage: "arrow.triangle.2.circlepath")
        .font(.title2.bold())
      if access.isChecking {
        ProgressView("Checking subscription…")
      } else if access.hasAccess {
        Label("Sync access is active", systemImage: "checkmark.shield")
        if access.renewalCancelled, let end = access.accessEnd {
          Text("Sync will stop on \(end.formatted(date: .abbreviated, time: .shortened)). Your downloaded data, local Apple Wallet features, and on-device Assistant will remain available.")
        }
      } else {
        Text("Start a subscription before entering credentials or connecting to a Sure server. Includes all supported devices and backends, with Family Sharing.")
        Text("Local Apple Wallet and on-device Assistant are always free. Downloaded data stays available when sync ends.")
          .foregroundStyle(.secondary)
        ForEach(access.plans) { plan in
          VStack(alignment: .leading, spacing: 6) {
            Text(plan.isAnnual ? "\(plan.price) per year" : "\(plan.price) per month")
              .font(.headline)
            if plan.hasTrial {
              Text("One week free, then renews automatically at the price above unless cancelled.")
                .font(.subheadline)
            } else {
              Text("Renews automatically unless cancelled.").font(.subheadline)
            }
            Button(plan.hasTrial ? "Start free trial" : "Subscribe") {
              Task { await access.purchase(plan) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(access.isBusy)
          }
        }
        if access.plans.isEmpty {
          Text("Subscription plans are currently unavailable.")
          Button("Try Again", systemImage: "arrow.clockwise") { Task { await access.refresh() } }
        }
        Text("A separate Sure account and compatible backend are required. Existing app.sure.am subscriptions are not yet recognized here.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let message = access.message { Text(message).foregroundStyle(.secondary) }
      Button("Restore Purchases", systemImage: "arrow.clockwise") { Task { await access.restore() } }
        .disabled(access.isBusy)
      Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
      HStack {
        Link("Privacy Policy", destination: URL(string: "https://sure.am/privacy")!)
        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
      }
      .font(.footnote)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
