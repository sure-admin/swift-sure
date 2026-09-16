import Foundation

@MainActor
struct CashFlowAPIClient: CashFlowProviding, SpendingComparisonClient {
  var transport: SureAPITransport

  func fetchSummary(for month: SpendingMonth) async throws -> CashFlow {
    let response = try await transport.send(APIRequest<CashFlowDTO>(method: .get,
      pathComponents: ["api", "v1", "cash_flow"],
      queryItems: [URLQueryItem(name: "month", value: month.start.iso8601String), URLQueryItem(name: "include", value: "sankey")]))
    let record: CashFlow
    do { record = try response.record() }
    catch { throw SureAPIError.decoding }
    guard record.month == month, record.sankey != nil else { throw SureAPIError.decoding }
    return record
  }

  func fetchComparison(for month: SpendingMonth) async throws -> SpendingComparison {
    try await fetchSummary(for: month).comparison
  }
}
