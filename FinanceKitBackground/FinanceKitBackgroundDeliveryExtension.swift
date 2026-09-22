import ExtensionFoundation
import FinanceKit

@available(iOS 26.0, *)
@main
final class FinanceKitBackgroundDeliveryExtension: BackgroundDeliveryExtension {
  required init() { }

  func didReceiveData(for types: [FinanceStore.BackgroundDataType]) async {
    let changedTypes = Set(types.compactMap(Self.map))
    await FinanceKitSyncRunner().runQuietly(changedTypes: changedTypes)
  }

  func willTerminate() async { }

  private static func map(
    _ type: FinanceStore.BackgroundDataType
  ) -> FinanceKitBackgroundDataType? {
    switch type {
    case .accounts: .accounts
    case .accountBalances: .accountBalances
    case .transactions: .transactions
    @unknown default: nil
    }
  }
}
