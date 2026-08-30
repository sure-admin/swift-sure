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
            Text("Sign in to connect your Sure account and see your complete financial picture.")
              .font(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }

          VStack(spacing: 12) {
            AppleSSOButton(
              isEnabled: connection.canSignInWithPasskey
                && connection.status != .connecting
            ) {
              Task { await connection.signIn(with: .apple) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .accessibilityHint("Opens Apple’s secure sign-in page")

            providerButton(.google)
          }

          statusView

          Spacer(minLength: 36)

          HStack(spacing: 4) {
            Text("Powered by:")
              .foregroundStyle(.secondary)
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

  private func providerButton(_ provider: SSOProvider) -> some View {
    Button {
      Task { await connection.signIn(with: provider) }
    } label: {
      HStack(spacing: 12) {
        providerIcon(provider)
          .frame(width: 22)
        Text("Continue with \(provider.displayName)")
          .font(.headline)
        Spacer()
      }
      .padding(.horizontal, 18)
      .frame(minHeight: 54)
      .foregroundStyle(.primary)
    }
    .liquidGlassButton(
      tint: provider == .apple
        ? Color.black.opacity(0.18)
        : SureTheme.highlight.opacity(0.75)
    )
    .disabled(!connection.canSignInWithPasskey || connection.status == .connecting)
    .accessibilityHint("Opens \(provider.displayName)’s secure sign-in page")
  }

  @ViewBuilder
  private func providerIcon(_ provider: SSOProvider) -> some View {
    switch provider {
    case .apple:
      Image(systemName: "apple.logo")
        .font(.title3)
        .accessibilityHidden(true)
    case .google:
      Text("G")
        .font(.system(size: 19, weight: .bold, design: .rounded))
        .foregroundStyle(.blue)
        .accessibilityHidden(true)
    }
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
