import Foundation

/// Prevent a public-demo request from redirecting outside the free host boundary.
final class DemoRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  static func allowsRedirect(from original: URL?, to destination: URL?) -> Bool {
    !SureDemoServer.allowsRequest(to: original)
      || SureDemoServer.allowsRequest(to: destination)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(Self.allowsRedirect(from: task.originalRequest?.url, to: request.url) ? request : nil)
  }
}
