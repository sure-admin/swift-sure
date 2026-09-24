import Foundation
import Testing
@testable import Sure

@Suite("First-run copy and configuration")
struct FirstRunCopyTests {
  @Test("Every variant and region has complete copy for both pitches")
  func completeCopy() {
    for variant in FirstRunCopyVariant.allCases {
      for region in FirstRunRegion.allCases {
        let copy = FirstRunCopy.make(variant: variant, market: .market(for: region), currentMonth: "September")
        for headline in [copy.wallet, copy.demo, copy.walletUnavailable] {
          #expect(!headline.title.isEmpty)
          #expect(!headline.body.isEmpty)
          #expect(!headline.callToAction.isEmpty)
        }
      }
    }
  }

  @Test("Variants carry the design's distinct headlines")
  func variantHeadlines() {
    let titles = FirstRunCopyVariant.allCases.map {
      FirstRunCopy.make(variant: $0, market: .standard, currentMonth: "September").wallet.title
    }
    #expect(Set(titles).count == FirstRunCopyVariant.allCases.count)
    #expect(titles.last == "How’s September going?")
  }

  @Test("The Wallet pitch names the market's Wallet sources")
  func walletSourcesInterpolated() {
    var market = FirstRunMarket.standard
    market.walletSources = "Monzo and Barclaycard"
    let copy = FirstRunCopy.make(variant: .instantReveal, market: market, currentMonth: "September")
    #expect(copy.wallet.body.contains("Monzo and Barclaycard"))
  }

  @Test("Regions resolve from the device locale")
  func regionFromLocale() {
    #expect(FirstRunRegion(locale: Locale(identifier: "en_US")) == .unitedStates)
    #expect(FirstRunRegion(locale: Locale(identifier: "en_GB")) == .unitedKingdom)
    #expect(FirstRunRegion(locale: Locale(identifier: "es_ES")) == .other)
  }

  @Test("Launch-argument overrides win over the locale; unknown values are ignored")
  func overrides() {
    let calendar = Calendar(identifier: .gregorian)
    let now = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
    let locale = Locale(identifier: "en_US")
    let overridden = FirstRunConfiguration.resolve(
      preferences: PreferencesStub(variant: "storyCards", region: "UK"), locale: locale, calendar: calendar, now: now
    )
    #expect(overridden.variant == .storyCards)
    #expect(overridden.region == .unitedKingdom)

    let fallback = FirstRunConfiguration.resolve(
      preferences: PreferencesStub(variant: "nope", region: "Mars"), locale: locale, calendar: calendar, now: now
    )
    #expect(fallback.variant == FirstRunConfiguration.defaultVariant)
    #expect(fallback.region == .unitedStates)
    #expect(fallback.currentMonth == "September")
    #expect(fallback.previousMonth == "August")
  }

  @Test("Showcase curves pass exactly through the design's checkpoints")
  func showcaseCurves() throws {
    let showcase = FirstRunShowcase.standard
    for curve in [showcase.demoCurve, showcase.walletCurve] {
      #expect(curve.current.count == 23)
      #expect(curve.previous.count == 30)
      let currentLast = try #require(curve.current.last)
      #expect(abs(currentLast - NSDecimalNumber(decimal: curve.currentTotal).doubleValue) < 0.001)
      #expect(abs(curve.previous[22] - NSDecimalNumber(decimal: curve.previousSameDayTotal).doubleValue) < 0.001)
      #expect(zip(curve.current, curve.current.dropFirst()).allSatisfy { $0 <= $1 })
    }
    #expect(showcase.demoCurve.delta == Decimal(string: "523.65"))
    #expect(showcase.income == showcase.outflows.reduce(0) { $0 + $1.amount })
  }
}

private struct PreferencesStub: FirstRunPreferences {
  var variant: String?
  var region: String?
  func hasCompletedFirstRun() -> Bool { false }
  func setHasCompletedFirstRun(_ completed: Bool) {}
  func variantOverride() -> String? { variant }
  func regionOverride() -> String? { region }
  func alwaysShowsFirstRun() -> Bool { false }
}
