import Foundation

enum APNsDeviceTokenFormatter {
  static func string(from data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
}
