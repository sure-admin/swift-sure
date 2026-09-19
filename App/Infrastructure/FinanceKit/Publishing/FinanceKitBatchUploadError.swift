enum FinanceKitBatchUploadError: Error, Equatable {
  case authentication
  case authorization
  case conflict
  case invalidResponse
  case publisherRevoked
  case rateLimited(retryAfter: Int?)
  case rejected
  case server(Int)
  case tooLarge
}
