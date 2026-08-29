import Foundation

struct ChatPollingPolicy {
  var maximumAttempts: Int
  var delay: Duration
  var sleep: (Duration) async throws -> Void

  static var live: ChatPollingPolicy {
    ChatPollingPolicy(
      maximumAttempts: 45,
      delay: .seconds(1),
      sleep: { delay in try await Task.sleep(for: delay) }
    )
  }
}
