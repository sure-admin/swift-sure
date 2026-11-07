enum ConnectionStatus: Equatable {
  case notConnected
  case connecting
  case requiresSecondFactor
  case connected
  case failed(String)

  var label: String {
    switch self {
    case .notConnected: "Not connected"
    case .connecting: "Connecting…"
    case .requiresSecondFactor: "Two-factor authentication required"
    case .connected: "Connected"
    case .failed: "Connection failed"
    }
  }
}
