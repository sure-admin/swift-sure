import Foundation

enum APNsEnvironment: String, Codable, Equatable, Sendable {
  case sandbox
  case production

  static var current: APNsEnvironment {
    #if targetEnvironment(simulator)
    return .sandbox
    #else
    guard let profileURL = Bundle.main.url(
      forResource: "embedded",
      withExtension: "mobileprovision"
    ), let profile = try? String(contentsOf: profileURL, encoding: .isoLatin1) else {
      return .production
    }
    let developmentEntitlement = "<key>aps-environment</key>\\s*<string>development</string>"
    return profile.range(of: developmentEntitlement, options: .regularExpression) == nil
      ? .production
      : .sandbox
    #endif
  }
}
