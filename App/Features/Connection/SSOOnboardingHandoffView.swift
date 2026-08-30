import SwiftUI

struct SSOOnboardingHandoffView: View {
  var context: MobileSSOOnboardingContext
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
            .multilineTextAlignment(.center)
          if let email = context.email {
            Text(email)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
          Text("Your identity is verified. The short account setup flow is coming next.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Button("Back to sign in", systemImage: "chevron.backward") {
            goBack()
          }
          .buttonStyle(.borderedProminent)
          .tint(SureTheme.accent)
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
      }
      .background(SureTheme.canvas.ignoresSafeArea())
    }
  }
}
