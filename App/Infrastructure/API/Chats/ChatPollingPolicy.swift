import Foundation

struct ChatPollingPolicy {
  var maximumAttempts: Int
  var delay: Duration
  var backoffMultiplier: Int = 1
  var maximumDelay: Duration = .seconds(5)
  var sleep: (Duration) async throws -> Void

  func delay(beforeAttempt attempt: Int) -> Duration {
    var result = delay
    for _ in 1..<max(1, attempt) { result = min(maximumDelay, result * max(1, backoffMultiplier)) }
    return result
  }

  static var live: ChatPollingPolicy {
    ChatPollingPolicy(
      maximumAttempts: 12,
      delay: .seconds(1),
      backoffMultiplier: 2,
      sleep: { delay in try await Task.sleep(for: delay) }
    )
  }
}
