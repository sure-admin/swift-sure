/// Persists first-run completion and exposes design overrides.
///
/// Overrides use raw strings so they can be set as launch arguments while
/// comparing variants, e.g. `-sureFirstRunVariant storyCards -sureFirstRunRegion UK
/// -sureFirstRunAlwaysShow YES`.
protocol FirstRunPreferences: Sendable {
  func hasCompletedFirstRun() -> Bool
  func setHasCompletedFirstRun(_ completed: Bool)
  func variantOverride() -> String?
  func regionOverride() -> String?
  func alwaysShowsFirstRun() -> Bool
}
