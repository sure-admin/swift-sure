import SwiftUI

#if os(iOS)
import UIKit
#endif

@main
struct AppDefinition: App {
  #if os(iOS)
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #endif

  init() {
    #if os(iOS)
    WatchInsightsSync.shared.activate()
    #endif
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
