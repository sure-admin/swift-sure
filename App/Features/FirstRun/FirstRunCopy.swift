import Foundation

/// Resolves launch-hero copy from the FirstRun string catalog.
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
  var walletPageLabel = String(localized: "first_run.page.wallet", table: "FirstRun")
  var demoPageLabel = String(localized: "first_run.page.demo", table: "FirstRun")
  var walletFootnote = String(localized: "first_run.footnote.wallet", table: "FirstRun")
  var walletUnavailableFootnote = String(localized: "first_run.footnote.wallet_unavailable", table: "FirstRun")
  var demoFootnote = String(localized: "first_run.footnote.demo", table: "FirstRun")

  static func make(variant: FirstRunCopyVariant, market: FirstRunMarket, currentMonth: String) -> FirstRunCopy {
    let walletUnavailable = Headline(
      title: walletTitle(variant: variant, currentMonth: currentMonth),
      body: String(format: String(localized: "first_run.wallet.unavailable.body", table: "FirstRun"),
        locale: .current, market.walletProducts),
      callToAction: String(localized: "first_run.action.explore_demo", table: "FirstRun")
    )
    switch variant {
    case .instantReveal:
      return FirstRunCopy(
        wallet: Headline(
          title: walletTitle(variant: variant, currentMonth: currentMonth),
          body: String(format: String(localized: "first_run.wallet.instant.body", table: "FirstRun"),
            locale: .current, market.walletSources),
          callToAction: String(localized: "first_run.action.see_spending", table: "FirstRun")
        ),
        demo: Headline(
          title: String(localized: "first_run.demo.instant.title", table: "FirstRun"),
          body: String(localized: "first_run.demo.instant.body", table: "FirstRun"),
          callToAction: String(localized: "first_run.action.explore_demo", table: "FirstRun")
        ),
        walletUnavailable: walletUnavailable
      )
    case .storyCards:
      return FirstRunCopy(
        wallet: Headline(
          title: walletTitle(variant: variant, currentMonth: currentMonth),
          body: String(format: String(localized: "first_run.wallet.story.body", table: "FirstRun"),
            locale: .current, currentMonth),
          callToAction: String(localized: "first_run.action.see_spending", table: "FirstRun")
        ),
        demo: Headline(
          title: String(localized: "first_run.demo.story.title", table: "FirstRun"),
          body: String(localized: "first_run.demo.story.body", table: "FirstRun"),
          callToAction: String(localized: "first_run.action.start_tour", table: "FirstRun")
        ),
        walletUnavailable: walletUnavailable
      )
    case .heroOverview:
      return FirstRunCopy(
        wallet: Headline(
          title: walletTitle(variant: variant, currentMonth: currentMonth),
          body: String(localized: "first_run.wallet.overview.body", table: "FirstRun"),
          callToAction: String(localized: "first_run.action.see_spending", table: "FirstRun")
        ),
        demo: Headline(
          title: String(localized: "first_run.demo.overview.title", table: "FirstRun"),
          body: String(localized: "first_run.demo.overview.body", table: "FirstRun"),
          callToAction: String(localized: "first_run.action.open_demo", table: "FirstRun")
        ),
        walletUnavailable: walletUnavailable
      )
    }
  }

  private static func walletTitle(variant: FirstRunCopyVariant, currentMonth: String) -> String {
    switch variant {
    case .instantReveal: String(localized: "first_run.wallet.instant.title", table: "FirstRun")
    case .storyCards: String(localized: "first_run.wallet.story.title", table: "FirstRun")
    case .heroOverview: String(format: String(localized: "first_run.wallet.overview.title", table: "FirstRun"),
      locale: .current, currentMonth)
    }
  }

  func pitch(_ kind: FirstRunPitch.Kind, walletAvailable: Bool) -> FirstRunPitch {
    switch kind {
    case .wallet:
      let headline = walletAvailable ? wallet : walletUnavailable
      return FirstRunPitch(
        kind: .wallet,
        action: walletAvailable ? .connectWallet : .exploreDemo,
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
