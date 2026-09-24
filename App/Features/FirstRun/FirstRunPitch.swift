/// One swipeable launch page: its artwork, copy, and what its button starts.
struct FirstRunPitch: Equatable, Identifiable, Sendable {
  enum Kind: Equatable, Sendable {
    case wallet
    case demo
  }

  enum Action: Equatable, Sendable {
    case connectWallet
    case exploreDemo
  }

  var kind: Kind
  var action: Action
  var badge: String
  var badgeSymbol: String
  var pageLabel: String
  var title: String
  var body: String
  var callToAction: String
  var footnote: String
  var footnoteSymbol: String

  var id: Kind { kind }
}
