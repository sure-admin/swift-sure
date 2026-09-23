import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit batch uploader")
struct FinanceKitHTTPBatchUploaderTests {
  @Test("A foreground receipt poll gives up after about thirty seconds as a pending import")
  func pollStopsAtTheAttemptLimit() async throws {
    let accepted = try HTTPDataTransportStub.Result.http(fixture: "financekit-receipt-accepted")
    let stub = HTTPDataTransportStub(
      Array(repeating: accepted, count: FinanceKitHTTPBatchUploader.defaultStatusAttemptLimit)
    )
    let uploader = makeUploader(stub)
    let configuration = try Self.configuration()

    await #expect(throws: FinanceKitSyncError.importPending) {
      try await uploader.status(Self.batch, configuration: configuration)
    }

    // Five attempts with 2, 4, 8 and 16 second waits between them: about thirty
    // seconds, rather than the roughly two hundred a ten-attempt poll spends.
    let requests = await stub.requests()
    #expect(FinanceKitHTTPBatchUploader.defaultStatusAttemptLimit == 5)
    #expect(requests.count == 5)
  }

  @Test("An applied receipt ends the poll on its first attempt")
  func pollStopsOnApplied() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "financekit-receipt-applied")])
    let receipt = try await makeUploader(stub).status(Self.batch, configuration: Self.configuration())

    let requests = await stub.requests()
    #expect(receipt.status == .applied)
    #expect(receipt.appliedAt == Date(timeIntervalSince1970: 1_789_725_604))
    #expect(receipt.errorCode == nil)
    #expect(requests.count == 1)
  }

  @Test("A failed receipt ends the poll and carries the server's reason")
  func pollStopsOnFailed() async throws {
    let stub = HTTPDataTransportStub([try .http(fixture: "financekit-receipt-failed")])
    let receipt = try await makeUploader(stub).status(Self.batch, configuration: Self.configuration())

    #expect(receipt.status == .failed)
    #expect(receipt.appliedAt == nil)
    #expect(receipt.errorCode == "mapping_version_conflict")
  }

  @Test("A protocol error body reaches the caller alongside the status classification")
  func uploadSurfacesProtocolErrorCode() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "financekit-batch-error", status: 409)
    ])
    let uploader = makeUploader(stub)
    let configuration = try Self.configuration()

    await #expect(throws: FinanceKitBatchUploadError(kind: .conflict, code: "sequence_conflict")) {
      try await uploader.upload(Self.batch, configuration: configuration)
    }
  }

  @Test("A failure without a protocol error body still classifies by status code")
  func uploadWithoutErrorBody() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: "", status: 429, headers: ["Retry-After": "12"])
    ])
    let uploader = makeUploader(stub)
    let configuration = try Self.configuration()

    await #expect(throws: FinanceKitBatchUploadError(kind: .rateLimited(retryAfter: 12), code: nil)) {
      try await uploader.upload(Self.batch, configuration: configuration)
    }
  }

  @Test("Revocation during a receipt retry prevents another authenticated request")
  func revocationDuringRetry() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let revocation = FinanceKitPublisherRevocationStore(fileURL: folder.appendingPathComponent("revoked"))
    let stub = HTTPDataTransportStub([try .http(fixture: "financekit-receipt-accepted")])
    let uploader = FinanceKitHTTPBatchUploader(dataTransport: stub, credential: "test-only",
      canUpload: { !revocation.isRevoked }, waitBeforeStatusRetry: { _ in try revocation.revoke() })
    let configuration = try Self.configuration()
    await #expect(throws: FinanceKitBatchUploadError.publisherRevoked) {
      try await uploader.status(Self.batch, configuration: configuration)
    }
    #expect(await stub.requests().count == 1)
  }

  private func makeUploader(_ stub: HTTPDataTransportStub) -> FinanceKitHTTPBatchUploader {
    FinanceKitHTTPBatchUploader(
      dataTransport: stub,
      credential: "publisher-secret",
      waitBeforeStatusRetry: { _ in }
    )
  }

  private static let batch = FinanceKitPendingBatch(
    id: UUID(uuidString: "50000000-0000-4000-8000-000000000001")!,
    sequence: 1,
    predecessorDigest: nil,
    payloadDigest: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
    body: Data("{}".utf8)
  )

  private static func configuration() throws -> FinanceKitPublisherConfiguration {
    let source = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    return try FinanceKitPublisherConfiguration(
      serverURL: URL(string: "https://sure.example")!,
      uploadURL: URL(string: "https://sure.example/api/v1/financekit/publishers/30000000-0000-4000-8000-000000000001/batches")!,
      connectionID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      publisherID: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
      generation: 3,
      streamID: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
      consent: FinanceKitUploadConsent(
        grantedAt: Date(timeIntervalSince1970: 1_789_689_600),
        selectedSourceAccountIDs: [source],
        uploadAuthorized: true,
        familyVisibilityAcknowledged: true,
        remoteProcessingAcknowledged: true
      ),
      accountBindings: [FinanceKitAccountBinding(
        sourceAccountID: source,
        lineageID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
        mappingVersion: 2
      )],
      maxRecordsPerBatch: 500,
      maxBytesPerBatch: 5_000_000
    )
  }
}
