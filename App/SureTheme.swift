import SwiftUI

enum SureTheme {
  static let canvas = Color(red: 0.965, green: 0.96, blue: 0.94)
  static let ink = Color(red: 0.09, green: 0.11, blue: 0.15)
  static let accent = Color(red: 0.071, green: 0.718, blue: 0.416)
  static let highlight = Color(red: 0.820, green: 0.980, blue: 0.875)

  static func accountColor(_ name: String) -> Color {
    switch name {
    case "teal": .teal
    case "purple": .purple
    case "orange": .orange
    default: .blue
    }
  }
}

struct SureCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(20)
      .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(.primary.opacity(0.06))
      }
  }
}

extension View {
  func sureCard() -> some View {
    modifier(SureCardModifier())
  }
}
