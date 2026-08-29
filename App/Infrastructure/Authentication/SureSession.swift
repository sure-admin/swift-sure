import Foundation

actor SureSession: SureRequestContextProviding {
  private var context: SureRequestContext?

  init(context: SureRequestContext? = nil) {
    self.context = context
  }

  func requestContext() throws -> SureRequestContext {
    guard let context else {
      throw SureSessionError.notConfigured
    }
    return context
  }

  @discardableResult
  func replaceContext(with newContext: SureRequestContext) -> SureRequestContext? {
    let previousContext = context
    context = newContext
    return previousContext
  }

  @discardableResult
  func clearContext() -> SureRequestContext? {
    let previousContext = context
    context = nil
    return previousContext
  }
}

protocol SureRequestContextProviding: Sendable {
  func requestContext() async throws -> SureRequestContext
}

enum SureSessionError: LocalizedError, Equatable {
  case notConfigured

  var errorDescription: String? {
    "Sure is not connected."
  }
}
