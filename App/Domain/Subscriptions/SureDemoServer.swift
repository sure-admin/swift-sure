import Foundation

/// The public demo is the sole Sure host available without a StoreKit entitlement.
enum SureDemoServer {
  static let baseURL = URL(string: "https://demo.sure.am")!

  static func matchesBaseURL(_ url: URL?) -> Bool {
    guard allowsRequest(to: url), let url else { return false }
    return url.path.isEmpty || url.path == "/"
  }

  static func allowsRequest(to url: URL?) -> Bool {
    guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
    return components.scheme?.lowercased() == "https"
      && components.host?.lowercased() == "demo.sure.am"
      && (components.port == nil || components.port == 443)
      && components.user == nil && components.password == nil
  }
}
