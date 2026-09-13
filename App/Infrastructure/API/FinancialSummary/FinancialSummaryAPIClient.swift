import Foundation

@MainActor
struct FinancialSummaryAPIClient: FinancialSummaryProviding, SpendingComparisonClient {
  var transport: SureAPITransport

  func fetchSummary(for month: SpendingMonth) async throws -> FinancialSummary {
    let response = try await transport.send(APIRequest<FinancialSummaryDTO>(method: .get,
      pathComponents: ["api", "v1", "financial_summary"],
      queryItems: [URLQueryItem(name: "month", value: month.start.iso8601String)]))
    let record: FinancialSummary
    do { record = try response.record() }
    catch { throw SureAPIError.decoding }
    guard record.month == month else { throw SureAPIError.decoding }
    return record
  }

  func fetchComparison(for month: SpendingMonth) async throws -> SpendingComparison {
    try await fetchSummary(for: month).comparison
  }
}
