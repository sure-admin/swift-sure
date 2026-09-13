import Foundation

struct ReadMetadata: Equatable, Sendable {
  enum Source: String, Sendable { case server, cache }
  var fetchedAt: Date
  var source: Source
  var failure: DataFailure?
}
