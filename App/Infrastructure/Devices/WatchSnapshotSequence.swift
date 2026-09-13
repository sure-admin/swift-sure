import Foundation

@MainActor
final class WatchSnapshotSequence {
  private let defaults: UserDefaults
  private let makeID: () -> UUID

  init(defaults: UserDefaults, makeID: @escaping () -> UUID = { UUID() }) {
    self.defaults = defaults; self.makeID = makeID
  }

  func next() -> (String, UInt64) {
    let stream = defaults.string(forKey: "watchSnapshotStream") ?? makeID().uuidString
    let prior = UInt64(defaults.string(forKey: "watchSnapshotSequence") ?? "0") ?? 0
    // A new stream also handles counter overflow without comparing wall clocks.
    let nextStream = prior == UInt64.max ? makeID().uuidString : stream
    let revision = prior == UInt64.max ? 1 : prior + 1
    defaults.set(nextStream, forKey: "watchSnapshotStream")
    defaults.set(String(revision), forKey: "watchSnapshotSequence")
    return (nextStream, revision)
  }
}
