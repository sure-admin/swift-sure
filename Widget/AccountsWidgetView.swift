import SwiftUI
import WidgetKit

struct AccountsWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: AccountsEntry

  var body: some View {
    Group {
      if let snapshot = entry.snapshot {
        switch family {
        case .accessoryRectangular:
          LockScreenAccounts(accounts: Array(entry.accounts.prefix(3)))
        case .systemSmall:
          AccountList(entry: entry, snapshot: snapshot, maxRows: 3, showsNetWorth: false)
        case .systemMedium:
          AccountList(entry: entry, snapshot: snapshot, maxRows: 4, showsNetWorth: true)
        default:
          AccountList(entry: entry, snapshot: snapshot, maxRows: 10, showsNetWorth: true)
        }
      } else {
        NotConnectedView(compact: family == .accessoryRectangular)
      }
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }
}

private struct AccountList: View {
  let entry: AccountsEntry
  let snapshot: AccountsWidgetSnapshot
  let maxRows: Int
  let showsNetWorth: Bool

  var body: some View {
    let accounts = entry.accounts
    let shown = Array(accounts.prefix(maxRows))
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text("Accounts")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer(minLength: 8)
        if showsNetWorth, let netWorth = entry.netWorth {
          Text(netWorth)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .privacySensitive()
            .accessibilityLabel(Text("Net worth \(netWorth)"))
        }
      }

      // Rows take the remaining space and are clipped, so the header and footer
      // stay visible at large Dynamic Type sizes.
      VStack(alignment: .leading, spacing: 4) {
        if shown.isEmpty {
          Text("No accounts to show")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        ForEach(shown) { account in
          AccountRow(account: account)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .clipped()

      HStack {
        if accounts.count > shown.count {
          Text("+\(accounts.count - shown.count) more")
        }
        Spacer(minLength: 0)
        Text("Updated \(snapshot.updatedAt, style: .relative) ago")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
  }
}

private struct AccountRow: View {
  let account: AccountsWidgetSnapshot.Account

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(account.name)
        .font(.footnote)
        .lineLimit(1)
        .privacySensitive()
      Spacer(minLength: 8)
      Text(account.balance)
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .privacySensitive()
    }
    .accessibilityElement(children: .combine)
  }
}

private struct LockScreenAccounts: View {
  let accounts: [AccountsWidgetSnapshot.Account]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if accounts.isEmpty {
        Text("No accounts to show")
      }
      ForEach(accounts) { account in
        HStack {
          Text(account.name)
            .lineLimit(1)
            .privacySensitive()
          Spacer(minLength: 4)
          Text(account.balance)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .privacySensitive()
        }
        .accessibilityElement(children: .combine)
      }
    }
    .font(.caption)
  }
}

private struct NotConnectedView: View {
  let compact: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if !compact {
        Image(systemName: "building.columns")
          .font(.title3)
          .accessibilityHidden(true)
      }
      Text("Open Sure to show your account balances.")
        .font(.caption)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
