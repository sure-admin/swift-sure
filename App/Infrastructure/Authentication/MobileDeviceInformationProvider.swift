import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
struct MobileDeviceInformationProvider {
  private static let deviceIDKey = "sure.mobileDeviceID.v1"

  private var defaults: UserDefaults
  private var makeID: () -> UUID

  init(
    defaults: UserDefaults = .standard,
    makeID: @escaping () -> UUID = { UUID() }
  ) {
    self.defaults = defaults
    self.makeID = makeID
  }

  func information() -> MobileDeviceInformation {
    MobileDeviceInformation(
      deviceID: stableDeviceID(),
      deviceName: deviceName,
      deviceType: "ios",
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      appVersion: Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "unknown"
    )
  }

  private func stableDeviceID() -> String {
    if let saved = defaults.string(forKey: Self.deviceIDKey), !saved.isEmpty {
      return saved
    }
    let value = makeID().uuidString.lowercased()
    defaults.set(value, forKey: Self.deviceIDKey)
    return value
  }

  private var deviceName: String {
    #if os(iOS)
    UIDevice.current.name
    #elseif os(macOS)
    Host.current().localizedName ?? "Mac"
    #endif
  }
}
