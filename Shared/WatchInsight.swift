import Foundation

struct WatchInsight: Codable, Equatable, Identifiable {
  var id: String
  var type: String
  var title: String
  var body: String
  var priority: String
  var generatedAt: Date?
}
