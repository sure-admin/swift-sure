#if os(iOS)
import Foundation
import WidgetKit

/// Keeps the home screen widget's snapshot in step with the finance store.
@MainActor
final class AccountsWidgetPublisher {
  private let store: AccountsWidgetSnapshotStore
  private let locale: Locale
  private let reloadWidgets: () -> Void

  init(
    store: AccountsWidgetSnapshotStore,
    locale: Locale = .autoupdatingCurrent,
    reloadWidgets: @escaping () -> Void = {
      WidgetCenter.shared.reloadTimelines(ofKind: AccountsWidgetSnapshot.widgetKind)
    }
  ) {
    self.store = store
    self.locale = locale
    self.reloadWidgets = reloadWidgets
  }

  /// Saves the update, or removes the snapshot when `update` is nil (disconnect or logout).
  func publish(_ update: AccountsWidgetUpdate?) {
    if let update {
      do {
        try store.save(AccountsWidgetPresentationMapping.snapshot(for: update, locale: locale))
      } catch {
        // Never leave an older snapshot (possibly another connection's) in place
        // when the current one can't be written.
        try? store.remove()
      }
    } else {
      try? store.remove()
    }
    reloadWidgets()
  }
}
#endif
