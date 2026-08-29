import Foundation

struct BackendInsight: Identifiable {
  var id: String
  var type: String
  var title: String
  var body: String
  var priority: String
  var status: String
  var generatedAt: Date?
}
