import Foundation

@MainActor
struct FirstRunAssembly {
  /// Nil when the launch hero should not appear: it already completed, a Sure
  /// connection is configured, or the platform has no full-screen launch.
  let store: FirstRunStore?

  init(connection services: ConnectionAssembly, finance: FinanceAssembly) {
    #if os(iOS)
    let preferences = UserDefaultsFirstRunPreferences()
    let isFirstRun = !preferences.hasCompletedFirstRun() && !services.connection.isConfigured
    guard isFirstRun || preferences.alwaysShowsFirstRun() else {
      store = nil
      return
    }
    let wallet = finance.appleCardConnection
    store = FirstRunStore(
      configuration: .resolve(
        preferences: preferences,
        locale: .autoupdatingCurrent,
        calendar: .autoupdatingCurrent,
        now: .now
      ),
      walletAvailable: wallet.isAvailable,
      connectWallet: {
        await wallet.connect()
        return wallet.state == .authorized
      },
      markCompleted: { preferences.setHasCompletedFirstRun(true) }
    )
    #else
    store = nil
    #endif
  }
}
