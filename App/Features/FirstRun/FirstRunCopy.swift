import Foundation

/// Copy catalog for the launch hero. Every user-visible first-run string lives
/// here so variants and regions can be compared without touching the views.
struct FirstRunCopy: Equatable, Sendable {
  struct Headline: Equatable, Sendable {
    var title: String
    var body: String
    var callToAction: String
  }

  var wallet: Headline
  var demo: Headline
  /// Replaces the Wallet pitch when FinanceKit is unavailable on this device.
  var walletUnavailable: Headline
  var walletBadge = String(localized: "On this iPhone")
  var demoBadge = String(localized: "Live demo")
  var walletPageLabel = String(localized: "Your Wallet")
  var demoPageLabel = String(localized: "Live demo")
  var walletFootnote = String(localized: "Stays on this iPhone. Nothing is uploaded.")
  var walletUnavailableFootnote = String(localized: "No Wallet accounts on this iPhone yet")
  var demoFootnote = String(localized: "Live demo data from demo.sure.am")

  static func make(variant: FirstRunCopyVariant, market: FirstRunMarket, currentMonth: String) -> FirstRunCopy {
    let walletUnavailable = Headline(
      title: walletTitle(variant: variant, currentMonth: currentMonth),
      body: String(localized: "When \(market.walletProducts) are in Wallet, Sure reads them right here on your iPhone."),
      callToAction: String(localized: "Explore the live demo")
    )
    switch variant {
    case .instantReveal:
      return FirstRunCopy(
        wallet: Headline(
          title: walletTitle(variant: variant, currentMonth: currentMonth),
          body: String(localized: "Sure reads \(market.walletSources) right here on your iPhone. One tap, no sign-up."),
          callToAction: String(localized: "See my spending")
        ),
        demo: Headline(
          title: String(localized: "A real month of money, made clear."),
          body: String(localized: "Explore Sure’s live demo account: where the money came from, where it went, and how this month compares."),
          callToAction: String(localized: "Explore the live demo")
        ),
        walletUnavailable: walletUnavailable
      )
    case .storyCards:
      return FirstRunCopy(
        wallet: Headline(
          title: walletTitle(variant: variant, currentMonth: currentMonth),
          body: String(localized: "We’ll read your Wallet accounts on this iPhone and show you how \(currentMonth) is going."),
          callToAction: String(localized: "See my spending")
        ),
        demo: Headline(
          title: String(localized: "Three cards. One real month of money."),
          body: String(localized: "Take a tour of Sure’s live demo account. No sign-up."),
          callToAction: String(localized: "Start the tour")
        ),
        walletUnavailable: walletUnavailable
      )
    case .heroOverview:
      return FirstRunCopy(
        wallet: Headline(
          title: walletTitle(variant: variant, currentMonth: currentMonth),
          body: String(localized: "Tap once and Sure will answer from your Wallet accounts, on this iPhone."),
          callToAction: String(localized: "See my spending")
        ),
        demo: Headline(
          title: String(localized: "Meet a year of real money."),
          body: String(localized: "Sure’s live demo account opens straight into cash flow and spending trends."),
          callToAction: String(localized: "Open the demo")
        ),
        walletUnavailable: walletUnavailable
      )
    }
  }

  private static func walletTitle(variant: FirstRunCopyVariant, currentMonth: String) -> String {
    switch variant {
    case .instantReveal: String(localized: "See where your money went this month.")
    case .storyCards: String(localized: "Your month, in three taps.")
    case .heroOverview: String(localized: "How’s \(currentMonth) going?")
    }
  }

  func pitch(_ kind: FirstRunPitch.Kind, walletAvailable: Bool) -> FirstRunPitch {
    switch kind {
    case .wallet:
      let headline = walletAvailable ? wallet : walletUnavailable
      return FirstRunPitch(
        kind: .wallet,
        action: walletAvailable ? .connectWallet : .exploreDemo,
        badge: walletBadge,
        badgeSymbol: "iphone",
        pageLabel: walletPageLabel,
        title: headline.title,
        body: headline.body,
        callToAction: headline.callToAction,
        footnote: walletAvailable ? walletFootnote : walletUnavailableFootnote,
        footnoteSymbol: walletAvailable ? "lock.fill" : "info.circle"
      )
    case .demo:
      return FirstRunPitch(
        kind: .demo,
        action: .exploreDemo,
        badge: demoBadge,
        badgeSymbol: "globe",
        pageLabel: demoPageLabel,
        title: demo.title,
        body: demo.body,
        callToAction: demo.callToAction,
        footnote: demoFootnote,
        footnoteSymbol: "globe"
      )
    }
  }
}
