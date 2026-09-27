import Foundation

struct SentryDiagnosticsConfiguration {
  let dsn: URL
  let environment: String

  /// A DSN is a public client key, but it still names a remote destination and
  /// is treated as untrusted build input: require HTTPS, reject an unexpanded
  /// build setting, and reject the deprecated secret component so no credential
  /// can be committed alongside it.
  init?(dsn: String, environment: String = SentryDiagnosticsConfiguration.defaultEnvironment) {
    let trimmed = dsn.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains("$("),
          !trimmed.contains(where: { $0.isWhitespace }),
          let components = URLComponents(string: trimmed),
          components.scheme == "https",
          let publicKey = components.user, !publicKey.isEmpty,
          components.password == nil,
          let hostname = components.host, !hostname.isEmpty,
          components.query == nil, components.fragment == nil,
          !components.path.split(separator: "/").isEmpty,
          let url = components.url,
          !environment.isEmpty, !environment.contains(where: { $0.isWhitespace }) else { return nil }
    self.dsn = url
    self.environment = environment
  }

  init?(bundle: Bundle) {
    self.init(dsn: bundle.object(forInfoDictionaryKey: "SureSentryDSN") as? String ?? "")
  }

  static var defaultEnvironment: String {
    #if DEBUG
    return "development"
    #else
    return "production"
    #endif
  }
}
