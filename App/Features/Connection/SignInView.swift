import SwiftUI

struct SignInView: View {
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var focusedField: Field?
  var subscriptionAccess: SubscriptionAccessStore
  @Bindable var connection: SureConnection
  var showConnectionSettings: () -> Void

  var body: some View {
    if subscriptionAccess.hasAccess || connection.isDemoServer {
      if let onboarding = connection.pendingSSOOnboarding {
        SSOOnboardingHandoffView(
          context: onboarding,
          signInWithPasskey: { Task { await connection.signInWithPasskey() } },
          goBack: connection.cancelSSOOnboarding
        )
      } else {
        signInContent
      }
    } else {
      NavigationStack {
        SubscriptionAccessView(access: subscriptionAccess)
          .toolbar {
            ToolbarItem(placement: .primaryAction) { settingsButton }
          }
      }
    }
  }

  private var signInContent: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 28) {
          Spacer(minLength: 44)

          VStack(spacing: 16) {
            SureLogo()
            Text("Your finances, made clear")
              .font(.largeTitle.bold())
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
            Text("Sign in to connect your Sure account and see your complete financial picture.")
              .font(.body)
              .foregroundStyle(.primary)
              .multilineTextAlignment(.center)
          }

          VStack(spacing: 12) {
            if subscriptionAccess.hasAccess { serverField }

            VStack(spacing: 10) {
              TextField("Email", text: $connection.email,
                prompt: Text("Email").foregroundStyle(fieldPromptColor))
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .textContentType(.username)
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background(.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
              SecureField("Password", text: $connection.password,
                prompt: Text("Password").foregroundStyle(fieldPromptColor))
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                  guard connection.canSignInWithPassword, connection.status != .connecting else { return }
                  Task { await connection.signInWithPassword() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background(.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
              if connection.requiresSecondFactor { secondFactorFields }
              Button {
                Task { await connection.signInWithPassword() }
              } label: {
                Label {
                  Text("Continue")
                } icon: {
                  ZStack {
                    Image(systemName: "arrow.right")
                      .opacity(connection.status == .connecting ? 0 : 1)
                    if connection.status == .connecting {
                      ProgressView()
                        .controlSize(.small)
                        .tint(colorScheme == .dark ? Color.black : Color.white)
                        .accessibilityHidden(true)
                    }
                  }
                  .frame(width: 20, height: 20)
                }
                  .font(.headline)
                  .frame(maxWidth: .infinity, minHeight: 48)
                  .foregroundStyle(.background)
                  .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
              }
              .buttonStyle(.plain)
              .disabled(!connection.canSignInWithPassword || connection.status == .connecting)
              .accessibilityLabel("Continue")
              .accessibilityValue(connection.status == .connecting ? Text("Signing in") : Text(""))
              if connection.requiresSecondFactor {
                Button("Cancel verification", action: connection.cancelSecondFactor)
                  .buttonStyle(.bordered)
                  .disabled(connection.status == .connecting)
              }
            }

            HStack {
              Rectangle().frame(height: 1).foregroundStyle(.primary.opacity(0.2))
              Text("OR").font(.caption.bold()).foregroundStyle(.primary)
              Rectangle().frame(height: 1).foregroundStyle(.primary.opacity(0.2))
            }

            AppleSSOButton(
              isEnabled: connection.canSignInWithPasskey
                && connection.status != .connecting
            ) {
              Task { await connection.signIn(with: .apple) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay {
              RoundedRectangle(cornerRadius: 14)
                .stroke(.primary.opacity(0.2))
                .allowsHitTesting(false)
            }
            .disabled(!connection.canSignInWithPasskey || connection.status == .connecting)
            .accessibilityHint("Opens Apple’s secure sign-in page")

            googleSSOButton
            passkeyButton
          }

          statusView

          Spacer(minLength: 36)

          HStack(spacing: 4) {
            Text("Powered by:")
              .fontWeight(.bold)
              .foregroundStyle(.primary)
            if let url = connection.serverWebsiteURL {
              Link(destination: url) {
                Text(connection.serverDisplayName)
                  .foregroundStyle(serverAttributionColor)
                  .underline()
                  .fixedSize(horizontal: false, vertical: true)
              }
              .buttonStyle(.plain)
              .layoutPriority(1)
              .accessibilityIdentifier("sign-in-server-attribution")
              .accessibilityLabel(Text("Sure server: \(connection.serverDisplayName)"))
              .accessibilityHint("Opens the Sure server website")
            } else {
              Text(connection.serverDisplayName)
                .foregroundStyle(serverAttributionColor)
                .accessibilityIdentifier("sign-in-server-attribution")
            }
          }
          .font(.caption.monospaced())
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: connection.requiresSecondFactor) { _, required in
        focusedField = required ? .authenticationCode : nil
      }
      .background(greenGradientBackground)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          settingsButton
        }
      }
    }
  }

  private var secondFactorFields: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Two-factor authentication").font(.headline)
      TextField("Authentication code", text: $connection.secondFactorCode,
        prompt: Text("Authentication code").foregroundStyle(fieldPromptColor))
        .textFieldStyle(.plain)
        .foregroundStyle(.primary)
        .textContentType(.oneTimeCode)
        .focused($focusedField, equals: .authenticationCode)
        .submitLabel(.go)
        .onSubmit {
          guard connection.canSignInWithPassword, connection.status != .connecting else { return }
          Task { await connection.signInWithPassword() }
        }
        #if os(iOS)
        .keyboardType(.numberPad)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        #endif
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .privacySensitive()
      Text(connection.secondFactorRejected
        ? "That code wasn’t accepted. Enter a new code."
        : "Enter the code from your authenticator app.")
        .font(.callout)
        .foregroundStyle(connection.secondFactorRejected ? Color.red : Color.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var serverField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Server URL").font(.caption.bold())
      TextField("Server URL", text: $connection.serverURL,
        prompt: Text("https://sure.example.com").foregroundStyle(fieldPromptColor))
        .textFieldStyle(.plain)
        .foregroundStyle(.primary)
        .textContentType(.URL)
        .focused($focusedField, equals: .server)
        .submitLabel(.next)
        .onSubmit { focusedField = .email }
        #if os(iOS)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        #endif
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("Server URL")
        .accessibilityHint("The HTTPS address of your Sure server")
      if !connection.canSignInWithPasskey {
        Text("Enter your Sure server’s HTTPS URL to enable sign-in.")
          .font(.caption)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var settingsButton: some View {
    Button("Settings", systemImage: "gearshape") { showConnectionSettings() }
      .labelStyle(.iconOnly)
  }

  private var googleSSOButton: some View {
    Button {
      Task { await connection.signIn(with: .google) }
    } label: {
      HStack(spacing: 10) {
        Image("GoogleLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 18, height: 18)
          .accessibilityHidden(true)
        Text("Continue with Google")
          .font(.headline)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(.primary)
      .background(
        .background.opacity(0.94),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(.primary.opacity(0.12))
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .disabled(!connection.canSignInWithPasskey || connection.status == .connecting)
    .accessibilityHint("Opens Google’s secure sign-in page")
  }

  private var passkeyButton: some View {
    Button {
      Task { await connection.signInWithPasskey() }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "person.badge.key.fill")
          .frame(width: 18, height: 18)
          .accessibilityHidden(true)
        Text("Continue with Passkey")
          .font(.headline)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(.primary)
      .background(
        .background.opacity(0.94),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(.primary.opacity(0.12))
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .disabled(!connection.canSignInWithPasskey || connection.status == .connecting)
    .accessibilityHint("Opens Sure’s secure passkey sign-in page")
  }

  @ViewBuilder
  private var statusView: some View {
    switch connection.status {
    case .connecting:
      HStack(spacing: 10) {
        Text("Signing in…")
        Button("Cancel", action: connection.cancelAuthentication)
      }
      .foregroundStyle(.primary)
      .accessibilityElement(children: .combine)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .foregroundStyle(.red)
        .multilineTextAlignment(.center)
    default:
      EmptyView()
    }
  }

  private var serverAttributionColor: Color {
    colorScheme == .dark ? .white : SureTheme.ink
  }

  private var fieldPromptColor: Color {
    colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.65)
  }

  private enum Field: Hashable {
    case server
    case email
    case password
    case authenticationCode
  }

  private var greenGradientBackground: some View {
    ZStack {
      Rectangle().fill(.background)
      LinearGradient(
        colors: colorScheme == .dark ? [
          SureTheme.highlight.opacity(0.04),
          SureTheme.accent.opacity(0.20),
          SureTheme.accent.opacity(0.35)
        ] : [
          Color(red: 0.80, green: 0.96, blue: 0.82),
          Color(red: 0.55, green: 0.84, blue: 0.61),
          Color(red: 0.25, green: 0.62, blue: 0.39)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      RadialGradient(
        colors: [.white.opacity(colorScheme == .dark ? 0.04 : 0.55), .clear],
        center: .topTrailing,
        startRadius: 20,
        endRadius: 360
      )
      RadialGradient(
        colors: [SureTheme.highlight.opacity(colorScheme == .dark ? 0.04 : 0.65), .clear],
        center: .bottomLeading,
        startRadius: 10,
        endRadius: 320
      )
    }
    .ignoresSafeArea()
  }
}
