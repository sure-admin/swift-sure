import Foundation

struct PushSubscriptionOperations {
  var register: @MainActor (String, APNsEnvironment) async throws -> UUID
  var unregister: @MainActor (UUID) async throws -> Void
}
