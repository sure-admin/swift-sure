import SwiftUI

#if os(iOS)
import UIKit
#endif

@main
struct AppDefinition: App {
  #if os(iOS)
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #endif

  @State private var connection: SureConnection
  @State private var financeData: FinanceDataStore
  private var notificationManager: any InsightNotificationControlling
  private var remoteAssistant: any RemoteAssistantClient

  init() {
    let connection = SureConnection.shared
    _connection = State(initialValue: connection)
    _financeData = State(initialValue: FinanceDataStore.shared)
    notificationManager = NotificationManager.shared
    remoteAssistant = SureAPIClient(connection: connection)
    #if os(iOS)
    WatchInsightsSync.shared.activate()
    #endif
  }

  var body: some Scene {
    WindowGroup {
      ContentView(
        connection: connection,
        financeData: financeData,
        notificationManager: notificationManager,
        remoteAssistant: remoteAssistant
      )
    }
  }
}
