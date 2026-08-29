import Foundation

struct WatchInsightsSnapshot: Codable, Equatable {
  var insights: [WatchInsight]
  var updatedAt: Date
}
