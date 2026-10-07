import SwiftUI

struct ContentView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  #if os(iOS)
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif
  var subscriptionAccess: SubscriptionAccessStore
  var connection: SureConnection
  var analytics: AnalyticsStore
  var telemetryBuildDetails: TelemetryBuildDetails
  var diagnostics: DiagnosticsStore
  var financeData: FinanceDataStore
  var spendingComparison: SpendingComparisonStore
  var appleCardConnection: AppleCardConnectionStore
  var firstRun: FirstRunStore?
  var financeKitSync: FinanceKitSyncStore
  var notificationManager: any InsightNotificationControlling
  var remoteAssistant: any RemoteAssistantClient
  var transactionHistoryStoreFactory: TransactionHistoryStoreFactory
  var localTransactionHistoryStoreFactory: TransactionHistoryStoreFactory
  var makeAssistantMessageID: () -> UUID
  var now: () -> Date

  @State private var selection: AppSection = .overview
  @State private var connectionPresentation: ConnectionPresentation?
  @State private var sectionWidth: CGFloat = 0
  @State private var sectionArrival: SectionArrival?
  @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.4, bounce: 0)))
  private var sectionDrag = SectionDrag()

  var body: some View {
    appTabs
    .onChange(of: connection.isConfigured, initial: true) { _, configured in
      if connection.allowsWalletPreview && !configured && appleCardConnection.isAvailable { selection = .accounts }
    }
    .onChange(of: connection.status) { _, status in
      if status == .notConnected && connection.isSignedOut {
        connectionPresentation = nil
      } else if status == .connected && connectionPresentation == .demoSignIn {
        connectionPresentation = nil
      }
    }
    .onChange(of: visibleScreen, initial: true) { _, screen in
      analytics.capture(.screenViewed(screen))
    }
    .environment(\.showConnectionSettings) {
      connectionPresentation = .settings
    }
    .sheet(item: $connectionPresentation) { presentation in
      switch presentation {
      case .settings:
        ConnectionSettingsView(subscriptionAccess: subscriptionAccess, connection: connection, analytics: analytics,
          telemetryBuildDetails: telemetryBuildDetails,
          diagnostics: diagnostics, financeKitSync: financeKitSync, wallet: appleCardConnection)
      case .demoSignIn:
        SignInView(subscriptionAccess: subscriptionAccess, connection: connection,
          showConnectionSettings: { connectionPresentation = .settings })
      }
    }
    #if os(iOS)
    .fullScreenCover(isPresented: .constant(firstRun?.isFinished == false), onDismiss: routeAfterFirstRun) {
      if let firstRun { FirstRunView(store: firstRun) }
    }
    #endif
  }

  // Routes once the cover has dismissed, so a follow-up sheet can present.
  private func routeAfterFirstRun() {
    switch firstRun?.outcome {
    case .walletConnected:
      // Overview shows the local Wallet spending comparison: the "wow" moment.
      selection = .overview
    case .exploreDemo:
      connection.prepareDemoSignIn()
      connectionPresentation = .demoSignIn
    case nil:
      break
    }
  }

  private var visibleScreen: UsageScreen {
    switch connectionPresentation {
    case .settings: return .connectionSettings
    case .demoSignIn: return .signIn
    case nil: break
    }
    switch selection {
    case .overview: return .overview
    case .assistant: return .assistant
    case .accounts: return .accounts
    case .budget: return .budget
    }
  }

  private var appTabs: some View {
    TabView(selection: $selection) {
      Tab("Overview", systemImage: "rectangle.grid.2x2.fill", value: .overview) {
        OverviewView(
          data: financeData,
          hasSyncAccess: hasBackendAccess,
          spendingComparison: spendingComparison,
          refreshWalletAccess: { await appleCardConnection.refresh() },
          notificationManager: notificationManager,
          transactionHistoryStoreFactory: transactionHistoryStoreFactory
        )
        .id(connection.sessionGeneration)
        .sectionSwipe(.overview, drag: sectionDrag, arrival: sectionArrival)
      }

      Tab("Assistant", systemImage: "sparkles", value: .assistant) {
        AssistantView(
          connection: connection,
          financeData: financeData,
          remoteAssistant: remoteAssistant,
          makeMessageID: makeAssistantMessageID,
          now: now
        )
        .id(connection.sessionGeneration)
        .sectionSwipe(.assistant, drag: sectionDrag, arrival: sectionArrival)
      }

      Tab("Accounts", systemImage: "building.columns.fill", value: .accounts) {
        AccountsView(
          data: financeData,
          hasSyncAccess: hasBackendAccess,
          appleCardConnection: appleCardConnection,
          transactionHistoryStoreFactory: transactionHistoryStoreFactory,
          localTransactionHistoryStoreFactory: localTransactionHistoryStoreFactory
        )
        .id(connection.sessionGeneration)
        .sectionSwipe(.accounts, drag: sectionDrag, arrival: sectionArrival)
      }

      Tab("Budget", systemImage: "chart.pie.fill", value: .budget) {
        BudgetView(data: financeData, hasSyncAccess: hasBackendAccess)
          .id(connection.sessionGeneration)
          .sectionSwipe(.budget, drag: sectionDrag, arrival: sectionArrival)
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sectionWidth = $0 }
    .simultaneousGesture(sectionSwipeGesture)
    .sensoryFeedback(.selection, trigger: sectionArrival)
  }

  private var hasBackendAccess: Bool {
    subscriptionAccess.gate.isAllowed(for: connection.connectedServerURL)
  }

  /// Content follows the finger only in compact layouts. Beside a sidebar, or
  /// with Reduce Motion on, the arriving section fades in instead of sliding.
  private var followsFinger: Bool {
    #if os(iOS)
    return !reduceMotion && horizontalSizeClass == .compact
    #else
    return false
    #endif
  }

  private var sectionSwipeGesture: some Gesture {
    DragGesture(minimumDistance: 24)
      .updating($sectionDrag) { value, drag, _ in
        guard followsFinger else { return }
        let swipe = SectionSwipe(value)
        // Lock the axis on the first update so a vertical scroll never shifts content sideways.
        if drag.section == nil {
          drag.section = selection
          drag.isHorizontal = swipe.isHorizontal
        }
        guard drag.isHorizontal, let section = drag.section else { return }
        drag.offset = swipe.dragOffset(from: section)
      }
      .onEnded(changeSection)
  }

  private func changeSection(_ value: DragGesture.Value) {
    let swipe = SectionSwipe(value)
    guard let destination = swipe.destination(from: selection) else { return }

    let start = followsFinger
      ? SectionArrival.Frame(
          offset: swipe.arrivalOffset(entering: destination, from: selection, width: sectionWidth),
          opacity: 1)
      : SectionArrival.Frame(offset: 0, opacity: 0)
    sectionArrival = SectionArrival(id: (sectionArrival?.id ?? 0) + 1, section: destination, start: start)
    selection = destination
  }
}

/// An in-progress swipe, tied to the section it started on so the reset after
/// a committed swipe never shifts the section that replaced it.
private struct SectionDrag {
  var section: AppSection?
  var isHorizontal = false
  var offset: CGFloat = 0
}

/// The section a swipe just selected and the frame its content enters from.
private struct SectionArrival: Equatable {
  struct Frame: Equatable {
    static let settled = Frame(offset: 0, opacity: 1)

    var offset: CGFloat
    var opacity: Double
  }

  var id: Int
  var section: AppSection
  var start: Frame
}

/// Moves one section's content with an in-progress swipe, then plays its
/// entrance when a swipe selects it.
private struct SectionSwipePresentation: ViewModifier {
  var section: AppSection
  var drag: SectionDrag
  var arrival: SectionArrival?

  func body(content: Content) -> some View {
    let start = arrival.flatMap { $0.section == section ? $0.start : nil } ?? .settled
    content
      .offset(x: drag.section == section ? drag.offset : 0)
      .keyframeAnimator(initialValue: SectionArrival.Frame.settled, trigger: arrival) { content, frame in
        content
          .offset(x: frame.offset)
          .opacity(frame.opacity)
      } keyframes: { _ in
        KeyframeTrack(\.offset) {
          MoveKeyframe(start.offset)
          SpringKeyframe(0, duration: 0.45, spring: .smooth)
        }
        KeyframeTrack(\.opacity) {
          MoveKeyframe(start.opacity)
          LinearKeyframe(1, duration: 0.2)
        }
      }
  }
}

private extension View {
  func sectionSwipe(_ section: AppSection, drag: SectionDrag, arrival: SectionArrival?) -> some View {
    modifier(SectionSwipePresentation(section: section, drag: drag, arrival: arrival))
  }
}

private extension SectionSwipe {
  init(_ value: DragGesture.Value) {
    self.init(translation: value.translation, predictedEndTranslation: value.predictedEndTranslation)
  }
}

private enum ConnectionPresentation: String, Identifiable {
  case settings, demoSignIn
  var id: Self { self }
}
