import SwiftUI

struct TransactionRow: View {
  var transaction: FinanceTransaction

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: transaction.symbol)
        .font(.body.weight(.semibold))
        .frame(width: 40, height: 40)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(transaction.merchant)
          .fontWeight(.semibold)
          .lineLimit(1)
        Text(transaction.category)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let code = transaction.formattedMerchantCategoryCode {
          Text("MCC \(code)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Merchant category code \(code)")
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(FinanceFormatters.currency(transaction.signedAmount))
          .font(.body.monospacedDigit().weight(.semibold))
          .foregroundStyle(transaction.kind == .income ? .green : .primary)
        Text(FinanceFormatters.monthAndDay(transaction.date))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 5)
    .accessibilityElement(children: .combine)
  }
}
