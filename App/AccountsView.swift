import SwiftUI

struct AccountsView: View {
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
          ForEach(SampleFinanceData.accounts) { account in
            accountCard(account)
          }
          addAccountCard
        }
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
        .padding()
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("Accounts")
    }
  }

  private func accountCard(_ account: FinanceAccount) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Image(systemName: account.kind.symbol)
          .frame(width: 42, height: 42)
          .background(SureTheme.accountColor(account.tintName).opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
          .foregroundStyle(SureTheme.accountColor(account.tintName))
        Spacer()
        Image(systemName: "ellipsis")
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(account.name)
          .font(.headline)
        Text(account.institution)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(account.balance, format: FinanceFormatters.currency)
          .font(.title2.bold())
        Spacer()
        Label {
          Text("\(account.change.formatted(.number.precision(.fractionLength(1))))%")
        } icon: {
          Image(systemName: account.change >= 0 ? "arrow.up.right" : "arrow.down.right")
        }
          .font(.caption.bold())
          .foregroundStyle(account.change >= 0 ? .green : .orange)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
    .sureCard()
    .accessibilityElement(children: .combine)
  }

  private var addAccountCard: some View {
    Button {
    } label: {
      VStack(spacing: 12) {
        Image(systemName: "plus")
          .font(.title2.bold())
          .frame(width: 48, height: 48)
          .background(SureTheme.accent, in: Circle())
          .foregroundStyle(SureTheme.ink)
        Text("Add an account")
          .font(.headline)
        Text("Connect or track one manually")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 170)
      .sureCard()
    }
    .buttonStyle(.plain)
  }
}
