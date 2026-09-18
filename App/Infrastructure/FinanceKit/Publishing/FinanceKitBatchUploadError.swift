enum FinanceKitBatchUploadError: Error, Equatable {
  case authentication
  case authorization
  case conflict
  case invalidResponse
  case rateLimited(retryAfter: Int?)
  case rejected
  case server(Int)
  case tooLarge
}
