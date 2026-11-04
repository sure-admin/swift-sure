import SwiftUI

struct ConnectionPresentationModifier: ViewModifier {
  @Binding var presentation: ConnectionPresentation?
  var subscriptionAccess: SubscriptionAccessStore
  var connection: SureConnection
  var analytics: (any UsageAnalyticsControlling)? = nil
  var telemetryBuildDetails = TelemetryBuildDetails(postHogProjectToken: nil, sentryDSN: nil)
  var diagnostics: (any DiagnosticsControlling)? = nil
  var financeKitSync: FinanceKitSyncStore? = nil
  var wallet: AppleCardConnectionStore? = nil

  func body(content: Content) -> some View {
    content
      .environment(\.showSignIn) { presentation = .signIn }
      .environment(\.showConnectionSettings) { presentation = .settings }
      .sheet(item: $presentation) { destination in
        switch destination {
        case .settings:
          ConnectionSettingsView(
            subscriptionAccess: subscriptionAccess, connection: connection, analytics: analytics,
            telemetryBuildDetails: telemetryBuildDetails, diagnostics: diagnostics,
            financeKitSync: financeKitSync, wallet: wallet,
            showSignIn: { presentation = .signIn }
          )
        case .signIn:
          SignInView(subscriptionAccess: subscriptionAccess, connection: connection,
            showConnectionSettings: { presentation = .settings })
        }
      }
  }
}
