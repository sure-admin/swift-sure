import Foundation

extension BackendInsight {
  var typeLabel: String {
    type.replacingOccurrences(of: "_", with: " ").capitalized
  }
}
