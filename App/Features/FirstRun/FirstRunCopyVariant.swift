/// The three copy directions explored in the first-run design. Each keeps the
/// same launch hero but pitches Wallet and the live demo differently.
enum FirstRunCopyVariant: String, CaseIterable, Sendable {
  /// Direction A: "See where your money went this month."
  case instantReveal
  /// Direction B: "Your month, in three taps."
  case storyCards
  /// Direction C: "How’s September going?"
  case heroOverview

  var displayName: String {
    switch self {
    case .instantReveal: "A · Instant reveal"
    case .storyCards: "B · Story cards"
    case .heroOverview: "C · Hero → Overview"
    }
  }
}
