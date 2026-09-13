import SwiftUI

struct SubscriptionAccessView: View {
  var access: SubscriptionAccessStore
  @State private var selectedID: String?

  private var selectedPlan: SubscriptionPlan? {
    access.plans.first { $0.id == selectedID } ?? access.plans.first
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if access.isChecking {
          ProgressView("Checking subscription…")
        } else if access.hasAccess {
          Label("Sync access is active", systemImage: "checkmark.shield")
            .font(.title2.bold())
          if access.renewalCancelled, let end = access.accessEnd {
            Text("Sync will stop on \(end.formatted(date: .abbreviated, time: .shortened)). Your downloaded data, local Apple Wallet features, and on-device Assistant will remain available.")
          }
        } else {
          introduction
          VStack(spacing: 12) {
            ForEach(access.plans) { plan in planCard(plan) }
          }
          if access.plans.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text("Subscription plans are currently unavailable.")
              Button("Try again", systemImage: "arrow.clockwise") {
                Task { await access.refresh() }
              }
              .disabled(access.isBusy)
            }
            .sureCard()
          }
          benefits
          VStack(alignment: .leading, spacing: 8) {
            Text("Before you start").font(.headline)
            Text("You’ll need a Sure server to connect to.")
              .foregroundStyle(.secondary)
            if let trial = selectedPlan?.trialDuration {
              Text("You’ll have \(trial) to try it out and decide.")
                .foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .sureCard()
        }
        if let message = access.message {
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
        footer
      }
      .frame(maxWidth: 560, alignment: .leading)
      .padding(20)
      .frame(maxWidth: .infinity)
    }
    .background(.background)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if !access.hasAccess, !access.isChecking, let plan = selectedPlan {
        purchaseBar(plan)
      }
    }
    .tint(SureTheme.accent)
  }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Your money,\nyour devices. Private.")
        .font(.largeTitle.bold())
        .fixedSize(horizontal: false, vertical: true)
      Text("One subscription that supports ongoing development of the Sure codebase.")
        .font(.body)
        .foregroundStyle(.secondary)
    }
  }

  private func planCard(_ plan: SubscriptionPlan) -> some View {
    let selected = selectedPlan?.id == plan.id
    return Button {
      selectedID = plan.id
    } label: {
      HStack(spacing: 14) {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .foregroundStyle(selected ? AnyShapeStyle(SureTheme.accent) : AnyShapeStyle(.quaternary))
          .accessibilityHidden(true)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            planDescription(plan)
            Spacer(minLength: 0)
            Text(plan.price).font(.title2.bold())
          }
          VStack(alignment: .leading, spacing: 8) {
            planDescription(plan)
            Text(plan.price).font(.title2.bold())
          }
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.background, in: RoundedRectangle(cornerRadius: 22))
      .overlay {
        RoundedRectangle(cornerRadius: 22)
          .stroke(selected ? AnyShapeStyle(SureTheme.accent) : AnyShapeStyle(.quaternary), lineWidth: 2)
      }
    }
    .overlay(alignment: .topTrailing) {
      if let savings = plan.savingsPercent {
        Text("SAVE \(savings)%")
          .font(.caption.bold())
          .padding(.horizontal, 10).padding(.vertical, 7)
          .foregroundStyle(SureTheme.ink)
          .background(SureTheme.highlight, in: Capsule())
          .padding(.trailing, 20)
          .offset(y: -14)
          .allowsHitTesting(false)
      }
    }
    .padding(.top, plan.savingsPercent == nil ? 0 : 12)
    .buttonStyle(.plain)
    .disabled(access.isBusy)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityHint("Selects this subscription plan")
  }

  private func planDescription(_ plan: SubscriptionPlan) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(plan.title).font(.headline)
      if let equivalent = plan.monthlyEquivalent {
        Text("\(equivalent) per month, billed once a year")
          .font(.subheadline).foregroundStyle(.secondary)
      } else {
        Text("Billed every \(plan.billingPeriod). Cancel any time.")
          .font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }

  private var benefits: some View {
    VStack(alignment: .leading, spacing: 18) {
      benefit("Connect your data", detail: "Read only. Any Sure servers that you host.", symbol: "building.columns")
      benefit("Every device, Swift native", detail: "iPhone now, iPad, Mac and Watch soon.", symbol: "iphone")
      if selectedPlan?.familyShareable == true {
        benefit("Up to 5 additional App Store users", detail: "Included through Family Sharing.", symbol: "person.2.fill")
      }
      benefit("Free stays free", detail: "Apple Card/Cash monthly spending and on-device Assistant chat stay free.", symbol: "shield.fill")
    }
  }

  private func benefit(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .foregroundStyle(SureTheme.accent)
        .frame(width: 20, height: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var footer: some View {
    VStack(spacing: 12) {
      Button("Restore purchases", systemImage: "arrow.clockwise") {
        Task { await access.restore() }
      }
      .disabled(access.isBusy)
      .frame(minHeight: 44)
      Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
        .frame(minHeight: 44)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 20) { legalLinks }
        VStack(spacing: 8) { legalLinks }
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
    .font(.headline)
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder private var legalLinks: some View {
    Link("Privacy Policy", destination: URL(string: "https://sure.am/privacy")!)
      .frame(minHeight: 44)
    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
      .frame(minHeight: 44)
  }

  private func purchaseBar(_ plan: SubscriptionPlan) -> some View {
    VStack(spacing: 10) {
      Button {
        Task { await access.purchase(plan) }
      } label: {
        HStack {
          if access.isBusy { ProgressView() }
          if let trial = plan.trialDuration {
            Text("Start \(trial) free")
          } else {
            Text("Subscribe")
          }
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 12)
        .foregroundStyle(SureTheme.ink)
        .background(SureTheme.accent, in: RoundedRectangle(cornerRadius: 16))
      }
      .buttonStyle(.plain)
      .disabled(access.isBusy)
      Text(plan.hasTrial
        ? String(localized: "Then \(plan.price) every \(plan.billingPeriod). Cancel any time.")
        : String(localized: "\(plan.price) every \(plan.billingPeriod). Cancel any time."))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Text("Renews automatically unless cancelled.")
        .font(.caption2).foregroundStyle(.secondary)
    }
    .frame(maxWidth: 560)
    .padding(.horizontal, 20).padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
  }
}
