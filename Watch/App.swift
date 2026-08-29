import SwiftUI

@main
struct AppDefinition: App {
  @State private var store: WatchInsightsStore

  init() {
    let codec = WatchInsightsSnapshotCodec()
    let receiver = WatchConnectivityInsightsReceiver(
      codec: codec,
      now: { .now }
    )
    let cache = UserDefaultsWatchInsightsCache(
      defaults: .standard,
      codec: codec
    )
    _store = State(
      initialValue: WatchInsightsStore(
        receiver: receiver,
        cache: cache,
        codec: codec
      )
    )
  }

  var body: some Scene {
    WindowGroup {
      ContentView(store: store)
    }
  }
}
