import Foundation

struct MobileSSOOnboardingContext: Equatable, Sendable {
  var linkingCode: String
  var email: String?
  var firstName: String?
  var lastName: String?
  var allowsAccountCreation: Bool
  var hasPendingInvitation: Bool
}
