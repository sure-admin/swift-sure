import Foundation

protocol RequestAuthorizing {
  func authorize(_ request: inout URLRequest)
}

struct UnauthenticatedRequestAuthorizer: RequestAuthorizing {
  func authorize(_ request: inout URLRequest) { }
}
