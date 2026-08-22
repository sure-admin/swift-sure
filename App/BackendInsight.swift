import Foundation

struct BackendInsight: Identifiable {
  var id: String
  var type: String
  var title: String
  var body: String
  var priority: String
  var status: String
  var periodStart: Date?
  var generatedAt: Date?

  var typeLabel: String {
    type.replacingOccurrences(of: "_", with: " ").capitalized
  }

  var periodLabel: String? {
    periodStart?.formatted(.dateTime.month(.wide))
  }
}
