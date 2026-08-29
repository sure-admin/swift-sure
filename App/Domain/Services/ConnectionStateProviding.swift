protocol ConnectionStateProviding: AnyObject {
  var isConfigured: Bool { get }
  var hasVerifiedAPIKey: Bool { get }
}
