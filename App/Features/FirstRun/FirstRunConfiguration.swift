import Foundation

/// Tunable inputs for the launch hero.
struct FirstRunConfiguration: Equatable, Sendable {
  var variant: FirstRunCopyVariant
  var region: FirstRunRegion
  var currentMonth: String
  var previousMonth: String
  /// The first page flips once to the other pitch after this delay unless the
  /// person has already swiped or tapped a page control.
  var autoAdvanceDelay: Duration = .seconds(5)

  static let defaultVariant = FirstRunCopyVariant.instantReveal

  static func resolve(
    preferences: any FirstRunPreferences,
    locale: Locale,
    calendar: Calendar,
    now: Date
  ) -> FirstRunConfiguration {
    let variant = preferences.variantOverride().flatMap(FirstRunCopyVariant.init(rawValue:)) ?? defaultVariant
    let region = preferences.regionOverride().flatMap(FirstRunRegion.init(rawValue:)) ?? FirstRunRegion(locale: locale)
    let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).locale(locale)
    let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
    return FirstRunConfiguration(
      variant: variant,
      region: region,
      currentMonth: now.formatted(style),
      previousMonth: previous.formatted(style)
    )
  }
}
