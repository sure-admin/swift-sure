import Foundation

/// Sample artwork for the launch hero, the native equivalent of a marketing
/// screenshot. These figures are never presented as the user's or Sure's
/// records: the stage is hidden behind an "illustration" accessibility label
/// and is replaced by real data once a source is connected.
struct FirstRunShowcase: Sendable {
  enum Tint: Sendable {
    case salary, sideIncome, housing, food, shopping, transport, utilities, entertainment, surplus
  }

  struct Flow: Identifiable, Sendable {
    var name: String
    var amount: Decimal
    var tint: Tint
    var id: String { name }
  }

  /// Cumulative daily spending. `Double` is used only for chart geometry;
  /// displayed totals come from the `Decimal` fields.
  struct Curve: Sendable {
    var current: [Double]
    var previous: [Double]
    var currentTotal: Decimal
    var previousSameDayTotal: Decimal
    var dayCount: Int

    var delta: Decimal { previousSameDayTotal - currentTotal }
    var elapsedDays: Int { current.count }
  }

  var currency: CurrencyCode
  var incomes: [Flow]
  var outflows: [Flow]
  var demoCurve: Curve
  var walletCurve: Curve
  var walletAccounts: [String]

  static let standard = FirstRunShowcase(
    currency: CurrencyCode("USD")!,
    incomes: [
      Flow(name: String(localized: "first_run.showcase.salary", table: "FirstRun"), amount: 8_400, tint: .salary),
      Flow(name: String(localized: "first_run.showcase.side_income", table: "FirstRun"), amount: 1_150, tint: .sideIncome)
    ],
    outflows: [
      Flow(name: String(localized: "first_run.showcase.housing", table: "FirstRun"), amount: 2_850, tint: .housing),
      Flow(name: String(localized: "first_run.showcase.food", table: "FirstRun"), amount: 1_120, tint: .food),
      Flow(name: String(localized: "first_run.showcase.shopping", table: "FirstRun"), amount: 780, tint: .shopping),
      Flow(name: String(localized: "first_run.showcase.transportation", table: "FirstRun"), amount: 640, tint: .transport),
      Flow(name: String(localized: "first_run.showcase.utilities", table: "FirstRun"), amount: 410, tint: .utilities),
      Flow(name: String(localized: "first_run.showcase.entertainment", table: "FirstRun"), amount: 290, tint: .entertainment),
      Flow(name: String(localized: "first_run.showcase.surplus", table: "FirstRun"), amount: 3_460, tint: .surplus)
    ],
    demoCurve: Curve(
      current: cumulative(days: 30, seed: 3, firstWeekday: 2, fixed: [1: 2_850], checkpoints: [(23, 4_188.65)]),
      previous: folded(cumulative(days: 31, seed: 17, firstWeekday: 6, fixed: [1: 2_850], checkpoints: [(23, 4_712.30), (31, 6_090)])),
      currentTotal: Decimal(string: "4188.65")!,
      previousSameDayTotal: Decimal(string: "4712.30")!,
      dayCount: 30
    ),
    walletCurve: Curve(
      current: cumulative(days: 30, seed: 7, firstWeekday: 2, checkpoints: [(23, 1_284.60)]),
      previous: folded(cumulative(days: 31, seed: 11, firstWeekday: 6, checkpoints: [(23, 1_496.80), (31, 2_041.30)])),
      currentTotal: Decimal(string: "1284.60")!,
      previousSameDayTotal: Decimal(string: "1496.80")!,
      dayCount: 30
    ),
    walletAccounts: [String(localized: "first_run.showcase.apple_card", table: "FirstRun"),
      String(localized: "first_run.showcase.apple_cash", table: "FirstRun")]
  )

  var income: Decimal { incomes.reduce(0) { $0 + $1.amount } }

  /// A deterministic, weekend-weighted spending path that passes exactly
  /// through each checkpoint, so the artwork matches the design on every run.
  static func cumulative(
    days: Int,
    seed: Int64,
    firstWeekday: Int,
    fixed: [Int: Double] = [:],
    checkpoints: [(day: Int, total: Double)]
  ) -> [Double] {
    var state = seed
    func random() -> Double {
      state = (state * 16_807) % 2_147_483_647
      return Double(state - 1) / 2_147_483_646
    }
    let weights = (0..<days).map { index -> Double in
      let weekday = (firstWeekday + index) % 7
      let weekend = weekday == 0 || weekday == 6 ? 1.7 : 1
      let spike = random() < 0.13 ? 2.6 : 1
      return (0.2 + random()) * weekend * spike
    }
    var increments = Array(repeating: 0.0, count: days)
    var previousDay = 0
    var previousTotal = 0.0
    for checkpoint in checkpoints {
      let range = (previousDay + 1)...checkpoint.day
      let fixedSum = range.reduce(0) { $0 + (fixed[$1] ?? 0) }
      let weightSum = weights[previousDay..<checkpoint.day].reduce(0, +)
      let remaining = checkpoint.total - previousTotal - fixedSum
      for day in range {
        increments[day - 1] = (fixed[day] ?? 0) + weights[day - 1] / weightSum * remaining
      }
      previousDay = checkpoint.day
      previousTotal = checkpoint.total
    }
    var running = 0.0
    return increments.prefix(previousDay).map { running += $0; return running }
  }

  /// Folds a 31-day month's final day into day 30 of a 30-day axis.
  static func folded(_ values: [Double]) -> [Double] {
    guard values.count > 30 else { return values }
    return Array(values.prefix(29)) + [values[values.count - 1]]
  }
}
