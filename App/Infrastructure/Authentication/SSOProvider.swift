import Foundation

enum SSOProvider: String, CaseIterable, Sendable {
  case google = "google_oauth2"
  case apple

  var displayName: String {
    switch self {
    case .google: "Google"
    case .apple: "Apple"
    }
  }
}
