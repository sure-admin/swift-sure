@MainActor
protocol ConnectionStateProviding: AnyObject {
  var isConfigured: Bool { get }
  var allowsWalletPreview: Bool { get }
  var sessionGeneration: Int { get }
}

extension ConnectionStateProviding {
  var allowsWalletPreview: Bool { !isConfigured }
}
