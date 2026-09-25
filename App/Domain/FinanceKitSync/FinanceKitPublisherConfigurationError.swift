import Foundation

enum FinanceKitPublisherConfigurationError: Error, Equatable {
  case invalidByteLimit
  case invalidConsent
  case invalidGeneration
  case invalidMapping
  case invalidProtocolVersion
  case invalidRecordLimit
  case invalidServerURL
  case invalidUploadURL
}
