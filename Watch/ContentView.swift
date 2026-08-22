import SwiftUI

struct ContentView: View {
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Net worth")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("$143,047")
              .font(.title2.bold())
            Label("5.5% this month", systemImage: "arrow.up.right")
              .font(.caption2)
              .foregroundStyle(.green)
          }

          Divider()

          Label("$3,478 left", systemImage: "chart.pie.fill")
            .font(.headline)
          ProgressView(value: 0.67)
            .tint(Color(red: 0.96, green: 0.82, blue: 0.37))

          Divider()

          Text("Recent")
            .font(.headline)
          watchRow("Whole Foods", amount: "−$86", symbol: "cart.fill")
          watchRow("Payroll", amount: "+$4,820", symbol: "briefcase.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
      }
      .navigationTitle("Sure")
    }
  }

  private func watchRow(_ name: String, amount: String, symbol: String) -> some View {
    HStack {
      Image(systemName: symbol)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text(name)
        .lineLimit(1)
      Spacer()
      Text(amount)
        .font(.caption.monospacedDigit())
    }
    .accessibilityElement(children: .combine)
  }
}
