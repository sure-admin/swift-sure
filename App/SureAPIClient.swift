import Foundation

struct SureAPIClient {
  var connection: SureConnection

  func request(path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
    guard let baseURL = URL(string: connection.serverURL),
          let url = URL(string: path, relativeTo: baseURL) else {
      throw SureAPIError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(connection.apiKey, forHTTPHeaderField: "X-Api-Key")
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw SureAPIError.invalidResponse
    }
    guard 200..<300 ~= httpResponse.statusCode else {
      if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
        throw SureAPIError.unauthorized
      }
      throw SureAPIError.server(httpResponse.statusCode)
    }
    return data
  }

  func createChat() async throws -> String {
    let data = try await request(
      path: "/api/v1/chats",
      method: "POST",
      body: ["title": "Sure for Apple"]
    )
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let identifier = findString(keys: ["id", "uuid"], in: object) else {
      throw SureAPIError.invalidResponse
    }
    return identifier
  }

  func sendMessage(_ content: String, chatID: String) async throws -> String {
    let data = try await request(
      path: "/api/v1/chats/\(chatID)/messages",
      method: "POST",
      body: ["content": content]
    )
    let object = try JSONSerialization.jsonObject(with: data)
    guard let response = findAssistantContent(in: object) else {
      throw SureAPIError.invalidResponse
    }
    return response
  }

  private func findString(keys: [String], in object: Any) -> String? {
    if let dictionary = object as? [String: Any] {
      for key in keys {
        if let value = dictionary[key] as? String { return value }
        if let value = dictionary[key] as? NSNumber { return value.stringValue }
      }
      for value in dictionary.values {
        if let match = findString(keys: keys, in: value) { return match }
      }
    } else if let array = object as? [Any] {
      for value in array {
        if let match = findString(keys: keys, in: value) { return match }
      }
    }
    return nil
  }

  private func findAssistantContent(in object: Any) -> String? {
    if let dictionary = object as? [String: Any] {
      if let role = dictionary["role"] as? String,
         role == "assistant",
         let content = dictionary["content"] as? String {
        return content
      }
      if let content = dictionary["content"] as? String { return content }
      if let message = dictionary["message"] as? String { return message }
      for value in dictionary.values {
        if let match = findAssistantContent(in: value) { return match }
      }
    } else if let array = object as? [Any] {
      for value in array.reversed() {
        if let match = findAssistantContent(in: value) { return match }
      }
    }
    return nil
  }
}

enum SureAPIError: LocalizedError {
  case invalidURL
  case invalidResponse
  case unauthorized
  case server(Int)

  var errorDescription: String? {
    switch self {
    case .invalidURL: "The Sure server URL is invalid."
    case .invalidResponse: "Sure returned an unexpected response."
    case .unauthorized: "The API key is invalid or lacks access."
    case .server(let code): "Sure returned server error \(code)."
    }
  }
}
