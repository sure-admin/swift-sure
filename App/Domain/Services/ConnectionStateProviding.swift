@MainActor
protocol ConnectionStateProviding: AnyObject {
  var isConfigured: Bool { get }
  var sessionGeneration: Int { get }
}
