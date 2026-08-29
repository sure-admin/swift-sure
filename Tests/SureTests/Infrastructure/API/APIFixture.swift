import Foundation

enum APIFixture {
  static func data(named name: String) throws -> Data {
    let bundle = Bundle(for: SureTestsBundleToken.self)
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
      throw APIFixtureError.missing(name)
    }
    return try Data(contentsOf: url)
  }
}

private final class SureTestsBundleToken { }

private enum APIFixtureError: Error {
  case missing(String)
}
