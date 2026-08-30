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
            Image(systemName: "checkmark.shield.fill")
              .font(.system(size: 54, weight: .semibold))
              .foregroundStyle(SureTheme.accent)
              .accessibilityHidden(true)
            Text("Your finances, made clear")
              .font(.largeTitle.bold())
              .multilineTextAlignment(.center)
            Text("Sign in to connect your Sure account and see your complete financial picture.")
              .font(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }

          VStack(spacing: 12) {
            providerButton(.apple)
            providerButton(.google)
          }

          statusView

          Button("Other ways to connect", systemImage: "ellipsis") {
            showConnectionSettings()
          }
          .buttonStyle(.bordered)

          VStack(spacing: 4) {
            Text("Connecting to")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(serverDisplayName)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 24)
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
      }
      .background(SureTheme.canvas.ignoresSafeArea())
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
      .foregroundStyle(
        provider == .apple
          ? AnyShapeStyle(.white)
          : AnyShapeStyle(.primary)
      )
      .background(
        provider == .apple ? Color.black : Color.white,
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        if provider == .google {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(.primary.opacity(0.14))
        }
      }
    }
    .buttonStyle(.plain)
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
}
