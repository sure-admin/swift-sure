import SwiftUI

struct LiquidGlassButtonModifier: ViewModifier {
  var tint: Color

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      content
        .buttonStyle(.glass(.regular.tint(tint)))
    } else {
      content
        .buttonStyle(.bordered)
        .tint(tint)
    }
  }
}

extension View {
  func liquidGlassButton(tint: Color = SureTheme.accent) -> some View {
    modifier(LiquidGlassButtonModifier(tint: tint))
  }
}
