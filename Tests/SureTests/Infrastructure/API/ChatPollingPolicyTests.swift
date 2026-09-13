import Foundation
import Testing
@testable import Sure

struct ChatPollingPolicyTests {
  @Test func boundedBackoff() {
    let policy = ChatPollingPolicy.live
    #expect((1...5).map { policy.delay(beforeAttempt: $0) } == [.seconds(1), .seconds(2), .seconds(4), .seconds(5), .seconds(5)])
    #expect(policy.maximumAttempts == 12)
  }
}
