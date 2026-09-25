import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit publisher configuration")
struct FinanceKitPublisherConfigurationTests {
  @Test("Every consented Wallet source requires one durable server lineage")
  func consentRequiresMappings() throws {
    let first = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let second = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    let consent = try FinanceKitUploadConsent(
      grantedAt: Date(timeIntervalSince1970: 1_700_000_000),
      selectedSourceAccountIDs: [first, second],
      uploadAuthorized: true,
      familyVisibilityAcknowledged: true,
      remoteProcessingAcknowledged: true
    )
    let binding = try FinanceKitAccountBinding(
      sourceAccountID: first,
      lineageID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      mappingVersion: 1
    )

    #expect(throws: FinanceKitPublisherConfigurationError.invalidMapping) {
      try configuration(consent: consent, bindings: [binding])
    }
  }

  @Test("A background upload cannot leave the authenticated Sure origin")
  func uploadOrigin() throws {
    let source = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let consent = try FinanceKitUploadConsent(
      grantedAt: Date(timeIntervalSince1970: 1_700_000_000),
      selectedSourceAccountIDs: [source],
      uploadAuthorized: true,
      familyVisibilityAcknowledged: true,
      remoteProcessingAcknowledged: true
    )
    let binding = try FinanceKitAccountBinding(
      sourceAccountID: source,
      lineageID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      mappingVersion: 1
    )

    #expect(throws: FinanceKitPublisherConfigurationError.invalidUploadURL) {
      try FinanceKitPublisherConfiguration(
        serverURL: URL(string: "https://sure.example")!,
        uploadURL: URL(string: "https://redirect.example/api/v1/financekit/batches")!,
        connectionID: UUID(),
        publisherID: UUID(),
        generation: 1,
        streamID: UUID(),
        consent: consent,
        accountBindings: [binding],
        maxRecordsPerBatch: 500,
        maxBytesPerBatch: 1_000_000
      )
    }
  }

  @Test("Upload consent is separate from Wallet authorization")
  func explicitUploadConsent() {
    #expect(throws: FinanceKitPublisherConfigurationError.invalidConsent) {
      try FinanceKitUploadConsent(
        grantedAt: Date(timeIntervalSince1970: 1_700_000_000),
        selectedSourceAccountIDs: [UUID()],
        uploadAuthorized: false,
        familyVisibilityAcknowledged: true,
        remoteProcessingAcknowledged: true
      )
    }
  }

  private func configuration(
    consent: FinanceKitUploadConsent,
    bindings: [FinanceKitAccountBinding]
  ) throws -> FinanceKitPublisherConfiguration {
    try FinanceKitPublisherConfiguration(
      serverURL: URL(string: "https://sure.example")!,
      uploadURL: URL(string: "https://sure.example/api/v1/financekit/batches")!,
      connectionID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      publisherID: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
      generation: 1,
      streamID: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
      consent: consent,
      accountBindings: bindings,
      maxRecordsPerBatch: 500,
      maxBytesPerBatch: 1_000_000
    )
  }
}
