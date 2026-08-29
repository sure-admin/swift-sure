import Foundation
import Testing
@testable import Sure

@Suite("Watch insights snapshot codec")
struct WatchInsightsSnapshotCodecTests {
  @Test("A typed snapshot round-trips through application context")
  func typedSnapshotRoundTrip() throws {
    let expected = snapshot()
    let codec = WatchInsightsSnapshotCodec()

    let context = try codec.applicationContext(for: expected)
    let decoded = try codec.snapshot(from: context, now: { .distantPast })

    #expect(decoded == expected)
    #expect(context["watchInsightsSnapshot"] is Data)
    #expect(context["insights"] is Data)
  }

  @Test("Legacy contexts use the injected clock when no timestamp exists")
  func legacyContext() throws {
    let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    let expectedInsights = snapshot().insights
    let context: [String: Any] = [
      "insights": try JSONEncoder().encode(expectedInsights)
    ]

    let decoded = try WatchInsightsSnapshotCodec().snapshot(
      from: context,
      now: { fixedNow }
    )

    #expect(decoded.insights == expectedInsights)
    #expect(decoded.updatedAt == fixedNow)
  }

  @Test("Malformed and missing contexts have distinct failures")
  func invalidContexts() {
    let codec = WatchInsightsSnapshotCodec()

    #expect(throws: WatchInsightsSnapshotCodingError.malformedPayload) {
      try codec.snapshot(
        from: ["watchInsightsSnapshot": Data("invalid".utf8)],
        now: { .distantPast }
      )
    }
    #expect(throws: WatchInsightsSnapshotCodingError.missingPayload) {
      try codec.snapshot(from: [:], now: { .distantPast })
    }
  }

  private func snapshot() -> WatchInsightsSnapshot {
    WatchInsightsSnapshot(
      insights: [
        WatchInsight(
          id: "insight-1",
          type: "budget",
          title: "On track",
          body: "Spending is within the plan.",
          priority: "medium",
          generatedAt: Date(timeIntervalSince1970: 1_799_999_000)
        )
      ],
      updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
  }
}
