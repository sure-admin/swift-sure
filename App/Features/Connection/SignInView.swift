import SwiftUI

struct SignInView: View {
  @Bindable var connection: SureConnection
  var showConnectionSettings: () -> Void

  var body: some View {
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
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }

          VStack(spacing: 12) {
            VStack(spacing: 10) {
              TextField("Email", text: $connection.email)
                .textContentType(.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
              SecureField("Password", text: $connection.password)
                .textContentType(.password)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
              Button("Continue", systemImage: "arrow.right") {
                Task { await connection.signInWithPassword() }
              }
              .font(.headline)
              .frame(maxWidth: .infinity, minHeight: 48)
              .foregroundStyle(.white)
              .background(.black, in: RoundedRectangle(cornerRadius: 14))
              .disabled(!connection.canSignInWithPassword || connection.status == .connecting)
            }

            HStack {
              Rectangle().frame(height: 1).foregroundStyle(.black.opacity(0.2))
              Text("OR").font(.caption.bold()).foregroundStyle(.black.opacity(0.6))
              Rectangle().frame(height: 1).foregroundStyle(.black.opacity(0.2))
            }

            AppleSSOButton(
              isEnabled: connection.canSignInWithPasskey
                && connection.status != .connecting
            ) {
              Task { await connection.signIn(with: .apple) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .accessibilityHint("Opens Apple’s secure sign-in page")

            googleSSOButton
            passkeyButton
          }

          statusView

          Spacer(minLength: 36)

          HStack(spacing: 4) {
            Text("Powered by:")
              .fontWeight(.bold)
              .foregroundStyle(.black)
            if let serverWebURL {
              Link(serverDisplayName, destination: serverWebURL)
                .foregroundStyle(.blue)
                .accessibilityHint("Opens the Sure server website")
            } else {
              Text(serverDisplayName)
                .foregroundStyle(.secondary)
            }
          }
          .font(.caption.monospaced())
          .lineLimit(1)
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
      }
      .background(greenGradientBackground)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Connection settings", systemImage: "gearshape") {
            showConnectionSettings()
          }
          .labelStyle(.iconOnly)
        }
      }
    }
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
      }
      .padding(.horizontal, 18)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(.black)
      .background(
        Color.white.opacity(0.94),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(.black.opacity(0.12))
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .frame(height: 48)
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
      }
      .padding(.horizontal, 18)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(.black)
      .background(
        Color.white.opacity(0.94),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(.black.opacity(0.12))
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .frame(height: 48)
    .disabled(!connection.canSignInWithPasskey || connection.status == .connecting)
    .accessibilityHint("Opens Sure’s secure passkey sign-in page")
  }

  @ViewBuilder
  private var statusView: some View {
    switch connection.status {
    case .connecting:
      HStack(spacing: 10) {
        ProgressView()
        Text("Opening secure sign-in…")
      }
      .foregroundStyle(.secondary)
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

  private var serverDisplayName: String {
    guard let url = URL(string: connection.serverURL), let host = url.host else {
      return connection.serverURL
    }
    return host
  }

  private var serverWebURL: URL? {
    URL(string: connection.serverURL)
  }

  private var greenGradientBackground: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.80, green: 0.96, blue: 0.82),
          Color(red: 0.55, green: 0.84, blue: 0.61),
          Color(red: 0.25, green: 0.62, blue: 0.39)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      RadialGradient(
        colors: [.white.opacity(0.55), .clear],
        center: .topTrailing,
        startRadius: 20,
        endRadius: 360
      )
      RadialGradient(
        colors: [SureTheme.highlight.opacity(0.65), .clear],
        center: .bottomLeading,
        startRadius: 10,
        endRadius: 320
      )
    }
    .ignoresSafeArea()
  }
}
