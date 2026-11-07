import Foundation

struct InsightsAPIClient {
  var transport: SureAPITransport

  func fetchInsights() async throws -> [BackendInsight] {
    let request = APIRequest<InsightCollectionDTO>(
      method: .get,
      pathComponents: ["api", "v1", "insights"],
      forbiddenResponse: .previewFeatureUnavailable
    )
    let response = try await transport.send(request)
    return response.insights.map(Self.map)
  }

  func acknowledgeInsight(id: UUID, requiredServerURL: URL? = nil) async throws {
    var request = APIRequest<Void>(
      method: .patch,
      pathComponents: ["api", "v1", "insights", id.uuidString, "acknowledge"],
      expectedStatusCodes: [204],
      forbiddenResponse: .authorization
    )
    request.requiredServerURL = requiredServerURL
    try await transport.send(request)
  }

  private static func map(_ dto: InsightDTO) -> BackendInsight {
    BackendInsight(
      id: dto.id.uuidString,
      type: dto.type,
      title: dto.title,
      body: dto.body,
      priority: dto.priority.rawValue,
      status: dto.status.rawValue,
      generatedAt: dto.generatedAt
    )
  }
}
