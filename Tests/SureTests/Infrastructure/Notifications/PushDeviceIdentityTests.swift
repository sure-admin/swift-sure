import Foundation
import Testing
@testable import Sure

struct PushDeviceIdentityTests {
  @Test("Installation proof is stable per normalized server and isolated across servers")
  func serverIsolation() throws {
    let secrets = PushSecretFake()
    let first = PushDeviceIdentity(secrets: secrets, makeSecret: { String(repeating: "ab", count: 32) })
    let second = PushDeviceIdentity(secrets: secrets, makeSecret: { String(repeating: "cd", count: 32) })
    let key = try first.key(for: URL(string: "https://SURE.EXAMPLE:443/")!)
    #expect(try second.key(for: URL(string: "https://sure.example")!) == key)
    #expect(try second.key(for: URL(string: "https://other.example")!) != key)
    #expect(secrets.values.count == 2)
    #expect(secrets.values.keys.allSatisfy { !$0.contains("example") })
  }
}

private final class PushSecretFake: SecretValueStoring, @unchecked Sendable {
  var values: [String: String] = [:]
  func value(for key: String, scope: SecretValueScope) -> String? { values[key] }
  func setValue(_ value: String, for key: String, scope: SecretValueScope) throws { values[key] = value }
  func removeValue(for key: String, scope: SecretValueScope) throws { values[key] = nil }
}
