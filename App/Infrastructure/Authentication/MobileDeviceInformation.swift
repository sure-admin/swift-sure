import Foundation

struct MobileDeviceInformation: Codable, Equatable, Sendable {
  var deviceID: String
  var deviceName: String
  var deviceType: String
  var osVersion: String
  var appVersion: String

  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
    case deviceName = "device_name"
    case deviceType = "device_type"
    case osVersion = "os_version"
    case appVersion = "app_version"
  }
}
