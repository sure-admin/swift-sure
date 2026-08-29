import Foundation

@MainActor
protocol NotificationStateStoring: AnyObject {
  var insightNotificationsEnabled: Bool { get set }
  var deviceToken: String? { get set }
  var legacySubscriptionID: UUID? { get set }
  var registrationError: String? { get set }
  var pendingInsightID: String? { get set }
  func loadSubscriptionState() throws -> StoredPushSubscriptionState
  func saveSubscriptionState(_ state: StoredPushSubscriptionState) throws
}
