import SwiftUI
import WidgetKit

struct AccountsWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: AccountsWidgetSnapshot.widgetKind,
      intent: AccountsWidgetIntent.self,
      provider: AccountsTimelineProvider()
    ) { entry in
      AccountsWidgetView(entry: entry)
    }
    .configurationDisplayName("Account Balances")
    .description("Balances from Sure's last account update.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
  }
}
