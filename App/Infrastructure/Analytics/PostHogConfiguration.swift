import Foundation

struct PostHogConfiguration {
  let projectToken: String
  let host: URL

  init?(projectToken: String, host: String) {
    let token = projectToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard token.hasPrefix("phc_"), !token.contains("$("),
          !token.contains(where: { $0.isWhitespace }),
          let components = URLComponents(string: host),
          components.scheme == "https", let hostname = components.host, !hostname.isEmpty,
          components.user == nil, components.password == nil,
          components.query == nil, components.fragment == nil,
          let url = components.url else { return nil }
    self.projectToken = token
    self.host = url
  }

  init?(bundle: Bundle) {
    self.init(
      projectToken: bundle.object(forInfoDictionaryKey: "SurePostHogProjectToken") as? String ?? "",
      host: bundle.object(forInfoDictionaryKey: "SurePostHogHost") as? String ?? ""
    )
  }
}
