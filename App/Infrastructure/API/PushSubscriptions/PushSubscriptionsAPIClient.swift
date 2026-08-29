import Foundation

struct PushSubscriptionsAPIClient {
  var transport: SureAPITransport

  func register(token: String, environment: APNsEnvironment) async throws -> UUID {
    let request = APIRequest<PushSubscriptionDTO>(
      method: .post,
      pathComponents: ["api", "v1", "push_subscriptions"],
      body: RegisterPushSubscriptionRequest(
        token: token,
        environment: environment,
        platform: .iOS
      ),
      expectedStatusCodes: [201]
    )
    return try await transport.send(request).id
  }

  func unregister(id: UUID) async throws {
    let request = APIRequest<Void>(
      method: .delete,
      pathComponents: ["api", "v1", "push_subscriptions", id.uuidString.lowercased()]
    )
    try await transport.send(request)
  }
}

private struct RegisterPushSubscriptionRequest: Encodable {
  var token: String
  var environment: APNsEnvironment
  var platform: PushSubscriptionDTO.Platform
}
