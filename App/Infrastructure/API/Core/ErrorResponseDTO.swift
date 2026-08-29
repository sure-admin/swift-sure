import Foundation

struct ErrorResponseDTO: Decodable, Equatable {
  var error: String
  var message: String?
  var details: ErrorDetailsDTO?
  var errors: [String]?

  var normalizedErrorCode: String {
    error
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: "_")
  }
}

enum ErrorDetailsDTO: Decodable, Equatable {
  case messages([String])
  case object

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let messages = try? container.decode([String].self) {
      self = .messages(messages)
      return
    }

    _ = try decoder.container(keyedBy: ErrorDetailCodingKey.self)
    self = .object
  }
}

private struct ErrorDetailCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}
