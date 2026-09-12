import SwiftUI

struct SureConnectionPrompt: View {
  @Environment(\.showConnectionSettings) private var showConnectionSettings
  var hasSyncAccess: Bool

  var body: some View {
    ContentUnavailableView {
      if hasSyncAccess {
        Label("Connect your Sure account", systemImage: "link.badge.plus")
      } else {
        Label("Sync paused", systemImage: "pause.circle")
      }
    } description: {
      if hasSyncAccess {
        Text("Sign in with a passkey or connect with an API key to load your finances.")
      } else {
        Text("A subscription is required to sync with Sure. Complete your in-app purchase to start your trial or subscription before connecting. Local Apple Wallet, on-device Assistant, and downloaded data remain available.")
      }
    } actions: {
      Button(
        hasSyncAccess ? "Connect to Sure" : "View subscription plans",
        systemImage: hasSyncAccess ? "link" : "creditcard"
      ) {
        showConnectionSettings()
      }
      .buttonStyle(.borderedProminent)
    }
  }
}
