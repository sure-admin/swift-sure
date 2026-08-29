import Foundation
import Network

// All mutable listener and continuation state is isolated to `queue`.
final class OAuthLoopbackServer: @unchecked Sendable {
  let redirectURL: URL

  private let listener: NWListener
  private let queue = DispatchQueue(label: "am.sure.insights.oauth-loopback")
  private var startContinuation: CheckedContinuation<Void, Error>?
  private var callbackContinuation: CheckedContinuation<URL, Error>?
  private var pendingCallback: URL?
  private var terminalError: Error?

  init(port: UInt16, path: String) throws {
    guard let networkPort = NWEndpoint.Port(rawValue: port),
          let redirectURL = URL(string: "http://127.0.0.1:\(port)\(path)") else {
      throw PasskeyOAuthError.invalidResponse
    }
    self.redirectURL = redirectURL
    listener = try NWListener(using: .tcp, on: networkPort)
  }

  func start() async throws {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        self.startContinuation = continuation
        self.listener.stateUpdateHandler = { [weak self] state in
          self?.handle(state)
        }
        self.listener.newConnectionHandler = { [weak self] connection in
          self?.accept(connection)
        }
        self.listener.start(queue: self.queue)
      }
    }
  }

  func waitForCallback() async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        if let pendingCallback = self.pendingCallback {
          continuation.resume(returning: pendingCallback)
        } else if let terminalError = self.terminalError {
          continuation.resume(throwing: terminalError)
        } else {
          self.callbackContinuation = continuation
        }
      }
    }
  }

  func cancel(with error: Error) {
    queue.async {
      guard self.pendingCallback == nil, self.terminalError == nil else { return }
      self.terminalError = error
      self.callbackContinuation?.resume(throwing: error)
      self.callbackContinuation = nil
      self.listener.cancel()
    }
  }

  private func handle(_ state: NWListener.State) {
    switch state {
    case .ready:
      startContinuation?.resume()
      startContinuation = nil
    case .failed(let error):
      terminalError = error
      startContinuation?.resume(throwing: error)
      startContinuation = nil
      callbackContinuation?.resume(throwing: error)
      callbackContinuation = nil
    case .cancelled:
      break
    default:
      break
    }
  }

  private func accept(_ connection: NWConnection) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
      guard let self else { return }
      if let error {
        connection.cancel()
        cancel(with: error)
        return
      }
      guard let data,
            let request = String(data: data, encoding: .utf8),
            let requestLine = request.split(separator: "\r\n", maxSplits: 1).first,
            requestLine.hasPrefix("GET "),
            let target = requestLine.split(separator: " ").dropFirst().first,
            let callbackURL = URL(string: "http://127.0.0.1:\(redirectURL.port!)\(target)") else {
        connection.cancel()
        cancel(with: PasskeyOAuthError.invalidResponse)
        return
      }

      let body = "You’re connected to Sure. You can close this window and return to the app."
      let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
      connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
        connection.cancel()
      })
      finish(with: callbackURL)
    }
  }

  private func finish(with url: URL) {
    pendingCallback = url
    callbackContinuation?.resume(returning: url)
    callbackContinuation = nil
    listener.cancel()
  }
}
