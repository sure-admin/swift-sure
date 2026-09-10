import Foundation

/// Lossless JSON for server-owned schemas and arguments; never parse financial prose.
indirect enum ToolJSONValue: Codable, Equatable, Sendable {
  case object([String: ToolJSONValue])
  case array([ToolJSONValue])
  case string(String)
  case number(Decimal)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() { self = .null }
    else if let result = try? value.decode(Bool.self) { self = .bool(result) }
    else if let result = try? value.decode(String.self) { self = .string(result) }
    else if let result = try? value.decode(Decimal.self) { self = .number(result) }
    else if let result = try? value.decode([ToolJSONValue].self) { self = .array(result) }
    else { self = .object(try value.decode([String: ToolJSONValue].self)) }
  }

  func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .object(let result): try value.encode(result)
    case .array(let result): try value.encode(result)
    case .string(let result): try value.encode(result)
    case .number(let result): try value.encode(result)
    case .bool(let result): try value.encode(result)
    case .null: try value.encodeNil()
    }
  }
}
