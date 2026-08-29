import Foundation
import Testing
@testable import Sure

@Suite("Sure authentication session")
struct SureSessionTests {
  @Test("Snapshots the base URL and authorization as one context")
  func snapshotsContext() async throws {
    let initialContext = try context(
      host: "one.sure.example",
      authorization: .apiKey("first-key")
    )
    let replacementContext = try context(
      host: "two.sure.example",
      authorization: .bearer("second-token")
    )
    let session = SureSession(context: initialContext)

    let previous = await session.replaceContext(with: replacementContext)
    let previousContext = try #require(previous)
    let currentContext = try await session.requestContext()

    #expect(previousContext.baseURL.host == "one.sure.example")
    #expect(authorizationValue(previousContext.authorization) == "api-key:first-key")
    #expect(currentContext.baseURL.host == "two.sure.example")
    #expect(authorizationValue(currentContext.authorization) == "bearer:second-token")
  }

  @Test("Concurrent snapshots never combine different contexts")
  func concurrentSnapshots() async throws {
    let firstContext = try context(
      host: "one.sure.example",
      authorization: .apiKey("first-key")
    )
    let secondContext = try context(
      host: "two.sure.example",
      authorization: .bearer("second-token")
    )
    let session = SureSession(context: firstContext)

    let allSnapshotsAreComplete = await withTaskGroup(of: Bool.self) { group in
      for index in 0..<100 {
        group.addTask {
          let replacement = index.isMultiple(of: 2) ? firstContext : secondContext
          await session.replaceContext(with: replacement)
          do {
            let snapshot = try await session.requestContext()
            return isKnownContext(snapshot)
          } catch {
            return false
          }
        }
      }

      var result = true
      for await isComplete in group {
        result = result && isComplete
      }
      return result
    }

    #expect(allSnapshotsAreComplete)
  }

  @Test("A cleared session fails without exposing credential data")
  func clearedSession() async throws {
    let session = SureSession(
      context: try context(
        host: "one.sure.example",
        authorization: .bearer("sensitive-token")
      )
    )

    _ = await session.clearContext()
    do {
      _ = try await session.requestContext()
      #expect(Bool(false))
    } catch let error as SureSessionError {
      #expect(error == .notConfigured)
      #expect(error.localizedDescription == "Sure is not connected.")
      #expect(!error.localizedDescription.contains("sensitive-token"))
    }
  }

  @Test("Rejects relative URLs and empty credentials without exposing them")
  func contextValidation() throws {
    do {
      _ = try SureRequestContext(
        baseURL: URL(string: "/relative")!,
        authorization: .bearer("sensitive-token")
      )
      #expect(Bool(false))
    } catch {
      #expect(error.localizedDescription == "The Sure server URL is invalid.")
      #expect(!error.localizedDescription.contains("sensitive-token"))
    }

    do {
      _ = try SureRequestContext(
        baseURL: URL(string: "http://sure.example")!,
        authorization: nil
      )
      #expect(Bool(false))
    } catch let error as SureRequestContextError {
      #expect(error == .invalidBaseURL)
    }

    for value in [
      "https://user@sure.example",
      "https://sure.example?token=private",
      "https://sure.example#private",
      "https://sure.example/%2E%2E/private"
    ] {
      #expect(throws: SureRequestContextError.invalidBaseURL) {
        try SureRequestContext(baseURL: URL(string: value)!, authorization: nil)
      }
    }

    do {
      _ = try SureRequestContext(
        baseURL: URL(string: "https://sure.example")!,
        authorization: .apiKey("")
      )
      #expect(Bool(false))
    } catch {
      #expect(error.localizedDescription == "The stored Sure authorization is invalid.")
    }
  }

  @Test("Normalizes a trailing base-URL slash")
  func baseURLNormalization() throws {
    let context = try SureRequestContext(
      baseURL: URL(string: "https://SURE.example:443/installation///")!,
      authorization: nil
    )

    #expect(context.baseURL.absoluteString == "https://sure.example/installation")
  }

  private func context(
    host: String,
    authorization: SureRequestAuthorization?
  ) throws -> SureRequestContext {
    try SureRequestContext(
      baseURL: URL(string: "https://\(host)")!,
      authorization: authorization
    )
  }

  private func authorizationValue(_ authorization: SureRequestAuthorization?) -> String? {
    switch authorization {
    case .bearer(let token): "bearer:\(token)"
    case .apiKey(let key): "api-key:\(key)"
    case nil: nil
    }
  }

  private func isKnownContext(_ context: SureRequestContext) -> Bool {
    switch (context.baseURL.host, context.authorization) {
    case ("one.sure.example", .apiKey("first-key")):
      true
    case ("two.sure.example", .bearer("second-token")):
      true
    default:
      false
    }
  }
}
