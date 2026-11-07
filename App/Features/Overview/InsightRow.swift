import SwiftUI

struct InsightRow: View {
  var insight: BackendInsight
  var isAcknowledging: Bool
  var acknowledge: () -> Void

  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dragOffset: CGFloat = 0

  var body: some View {
    ZStack(alignment: .trailing) {
      Text("Dismiss")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.tint)
        .padding(.horizontal, 12)
        .opacity(dragOffset == 0 ? 0 : 1)
        .accessibilityHidden(true)
      HStack(alignment: .top) {
        content
        Spacer(minLength: 0)
        if isAcknowledging {
          ProgressView().accessibilityLabel("Dismissing insight")
        }
        #if os(macOS)
        Button("Dismiss", action: acknowledge)
          .buttonStyle(.bordered)
          .disabled(isAcknowledging)
        #endif
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.background)
      .offset(x: dragOffset)
    }
    .clipped()
    .contentShape(Rectangle())
    .simultaneousGesture(
      DragGesture(minimumDistance: 24)
        .onChanged { value in
          guard !isAcknowledging,
                abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
          let direction: CGFloat = layoutDirection == .rightToLeft ? 1 : -1
          dragOffset = direction * min(120, max(0, value.translation.width * direction))
        }
        .onEnded { value in
          let direction: CGFloat = layoutDirection == .rightToLeft ? 1 : -1
          let shouldDismiss = !isAcknowledging && value.translation.width * direction >= 88
            && abs(value.translation.width) > abs(value.translation.height) * 1.5
          withAnimation(reduceMotion ? nil : .snappy) { dragOffset = 0 }
          if shouldDismiss { acknowledge() }
        }
    )
    .contextMenu {
      Button("Dismiss insight", action: acknowledge).disabled(isAcknowledging)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("insight-" + insight.id)
    .accessibilityHint("Swipe to dismiss this insight")
    .accessibilityAction(named: Text("Dismiss insight")) {
      if !isAcknowledging { acknowledge() }
    }
  }

  private var content: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol(for: insight.type))
        .frame(width: 38, height: 38)
        .background(tint(for: insight.type).opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
        .foregroundStyle(tint(for: insight.type))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(insight.typeLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(insight.title)
          .fontWeight(.semibold)
        Text(insight.body)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
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
