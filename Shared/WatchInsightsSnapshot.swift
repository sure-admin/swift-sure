import Foundation

struct WatchInsightsSnapshot: Codable, Equatable {
  var insights: [WatchInsight]
  var updatedAt: Date
  var streamID: String? = nil
  var revision: UInt64? = nil
}
