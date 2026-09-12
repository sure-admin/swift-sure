import Charts
import SwiftUI

struct SpendingComparisonChart: View {
  var comparison: SpendingComparison
  var isWallet = false
  @State private var selectedDay: Int?
  @State private var showingExplanation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        Text("\(FinanceFormatters.fullDate(comparison.month.start)) to \(FinanceFormatters.fullDate(comparison.current.last!.date))")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("About spending comparison", systemImage: "info.circle") {
          showingExplanation = true
        }
        .labelStyle(.iconOnly)
        .popover(isPresented: $showingExplanation) {
          Text(isWallet
            ? LocalizedStringKey("Wallet spending stays on this device. It includes posted debits, excluding transfers. Credits and refunds aren’t deducted. Current-month totals compare the same elapsed days; past months compare full totals. The previous line shows its full month, folding any extra days into the final point.")
            : LocalizedStringKey("Spending totals come from Sure. The current month compares spending through the same day of the previous month. Past months compare full totals. The previous month’s line always shows its full total; extra days in a longer previous month are included in the final point."))
            .padding()
            .frame(idealWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
      }

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 24) {
          currentSummary
          Spacer(minLength: 16)
          previousSummary
        }
        VStack(alignment: .leading, spacing: 12) {
          currentSummary
          previousSummary
        }
      }

      if comparison.isEmpty {
        Text("No spending in either month")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120)
      } else {
        chart
        if let selectedDay {
          dailyDetails(day: selectedDay)
        }
      }
    }
  }

  private var currentSummary: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(monthLabel(comparison.month))
        .font(.caption)
      Text(money(comparison.currentTotal))
        .font(.title3.bold())
      Label {
        if comparison.delta < 0 {
          Text("\(money(-comparison.delta)) less")
        } else if comparison.delta > 0 {
          Text("\(money(comparison.delta)) more")
        } else {
          Text("No change")
        }
      } icon: {
        Image(systemName: comparison.delta < 0 ? "arrow.down" : comparison.delta > 0 ? "arrow.up" : "equal")
      }
      .font(.caption)
      .foregroundStyle(comparison.delta > 0 ? Color.red : comparison.delta < 0 ? Color.green : Color.secondary)
    }
    .padding(.leading, 10)
    .overlay(alignment: .leading) { Capsule().fill(.green).frame(width: 3) }
    .accessibilityElement(children: .combine)
  }

  private var previousSummary: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(monthLabel(comparison.month.shifted(by: -1)))
        .font(.caption)
      if comparison.comparisonDay < comparison.previous.count {
        Text("Days 1–\(comparison.comparisonDay)")
          .font(.caption)
      }
      Text(money(comparison.previousTotal))
        .font(.title3.bold())
    }
    .foregroundStyle(.secondary)
    .padding(.leading, 10)
    .overlay(alignment: .leading) { Capsule().fill(.gray).frame(width: 3) }
    .accessibilityElement(children: .combine)
  }

  private var chart: some View {
    Chart {
      ForEach(comparison.previousPlot.indices, id: \.self) { index in
        let point = comparison.previousPlot[index]
        LineMark(
          x: .value("Day", index + 1),
          y: .value("Spending", coordinate(point.amount)),
          series: .value("Month", "previous")
        )
        .foregroundStyle(.gray)
        .lineStyle(StrokeStyle(lineWidth: 1.5))
        .interpolationMethod(.monotone)
        .accessibilityLabel(FinanceFormatters.fullDate(point.date))
        .accessibilityValue(money(point.amount))
      }
      ForEach(comparison.current, id: \.date) { point in
        LineMark(
          x: .value("Day", point.date.day),
          y: .value("Spending", coordinate(point.amount)),
          series: .value("Month", "current")
        )
        .foregroundStyle(.green)
        .lineStyle(StrokeStyle(lineWidth: 2))
        .interpolationMethod(.monotone)
        .accessibilityLabel(FinanceFormatters.fullDate(point.date))
        .accessibilityValue(money(point.amount))
      }
      if let last = comparison.current.last {
        PointMark(x: .value("Day", last.date.day), y: .value("Spending", coordinate(last.amount)))
          .foregroundStyle(.green)
          .symbolSize(28)
          .accessibilityHidden(true)
      }
      if let selectedDay {
        RuleMark(x: .value("Day", selectedDay))
          .foregroundStyle(.secondary.opacity(0.4))
          .accessibilityHidden(true)
      }
    }
    .chartXScale(domain: 1...comparison.month.dayCount)
    .chartXAxis {
      AxisMarks(values: [1, (comparison.month.dayCount + 1) / 2, comparison.month.dayCount]) { value in
        AxisValueLabel(anchor: value.as(Int.self) == 1 ? .topLeading : value.as(Int.self) == comparison.month.dayCount ? .topTrailing : .top) {
          if let day = value.as(Int.self), let date = try? comparison.month.date(day: day) {
            Text(FinanceFormatters.monthAndDay(date))
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
        AxisGridLine(stroke: StrokeStyle(dash: [3, 4]))
        AxisValueLabel {
          if let amount = value.as(Double.self) {
            Text(FinanceFormatters.compactCurrency(DecimalMoney(amount: Decimal(amount), currency: comparison.currency)))
          }
        }
      }
    }
    .chartXSelection(value: $selectedDay)
    .frame(height: 200)
    .accessibilityLabel("Cumulative spending comparison")
    .accessibilityHint("Daily totals for the selected and previous months")
  }

  private func dailyDetails(day: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if day > 0, day <= comparison.current.count {
        let point = comparison.current[day - 1]
        Text("\(FinanceFormatters.fullDate(point.date)): \(money(point.amount))")
      }
      if day > 0, day <= comparison.previousPlot.count {
        let point = comparison.previousPlot[day - 1]
        Text("\(FinanceFormatters.fullDate(point.date)): \(money(point.amount))")
          .foregroundStyle(.secondary)
      }
    }
    .font(.caption)
    .accessibilityElement(children: .combine)
  }

  private func monthLabel(_ month: SpendingMonth) -> String {
    FinanceFormatters.monthAndYear(month.start, calendar: Calendar(identifier: .gregorian))
  }

  private func money(_ amount: Decimal) -> String {
    FinanceFormatters.currency(DecimalMoney(amount: amount, currency: comparison.currency))
  }

  // Floating point is used only for chart geometry, never financial totals.
  private func coordinate(_ amount: Decimal) -> Double {
    NSDecimalNumber(decimal: amount).doubleValue
  }
}
