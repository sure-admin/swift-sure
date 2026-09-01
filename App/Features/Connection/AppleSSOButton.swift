import AuthenticationServices
import SwiftUI

#if os(iOS)
import UIKit

struct AppleSSOButton: UIViewRepresentable {
  var isEnabled: Bool
  var action: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
    let button = ASAuthorizationAppleIDButton(
      authorizationButtonType: .continue,
      authorizationButtonStyle: .black
    )
    button.cornerRadius = 14
    button.addTarget(
      context.coordinator,
      action: #selector(Coordinator.activate),
      for: .touchUpInside
    )
    return button
  }

  func updateUIView(
    _ button: ASAuthorizationAppleIDButton,
    context: Context
  ) {
    context.coordinator.action = action
    button.isEnabled = isEnabled
  }

  @MainActor
  final class Coordinator: NSObject {
    var action: () -> Void

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @objc func activate() {
      action()
    }
  }
}
#else
struct AppleSSOButton: View {
  var isEnabled: Bool
  var action: () -> Void

  var body: some View {
    Button("Continue with Apple", systemImage: "apple.logo", action: action)
      .buttonStyle(.borderedProminent)
      .tint(.black)
      .disabled(!isEnabled)
  }
}
#endif
