struct BalanceSheetAPIClient {
  var transport: SureAPITransport

  func fetch() async throws -> BalanceSheetRecord {
    let response = try await transport.send(
      APIRequest<BalanceSheetDTO>(
        method: .get,
        pathComponents: ["api", "v1", "balance_sheet"]
      )
    )
    return try response.record()
  }
}
