import SwiftUI

struct SSOOnboardingHandoffView: View {
  var context: MobileSSOOnboardingContext
  var signInWithPasskey: () -> Void
  var goBack: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          Spacer(minLength: 72)
          Image(systemName: "person.crop.circle.badge.plus")
            .font(.system(size: 58))
            .foregroundStyle(SureTheme.accent)
            .accessibilityHidden(true)
          Text("Let’s set up your Sure account")
            .font(.largeTitle.bold())
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
          if let email = context.email {
            Text(email)
              .foregroundStyle(.black.opacity(0.65))
              .textSelection(.enabled)
          }
          Text("Your identity is verified. The short account setup flow is coming next.")
            .foregroundStyle(.black.opacity(0.65))
            .multilineTextAlignment(.center)
          Button("I already have an account", systemImage: "person.badge.key.fill") {
            signInWithPasskey()
          }
          .buttonStyle(.borderedProminent)
          .tint(.black)
          .accessibilityHint("Signs in to your existing Sure account with a passkey")
          Button("Back to sign in", systemImage: "chevron.backward") {
            goBack()
          }
          .buttonStyle(.bordered)
          .tint(.black)
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
      }
      .background(SureTheme.canvas.ignoresSafeArea())
    }
  }
}
