import SwiftUI

/// Sure brand colors used by the launch hero artwork. The hero always renders
/// light cards over a dark photo, so these do not adapt to dark mode.
enum FirstRunPalette {
  static let green = Color(hex: 0x10A861)
  static let greenDark = Color(hex: 0x078C52)
  static let chartInk = Color(hex: 0x171717)
  static let chartLabel = Color(hex: 0x737373)
  static let previousLine = Color(hex: 0xCFCFCF)
  static let glow = Color(hex: 0x05603A)
  static let night = Color(hex: 0x0B0B0B)

  static func color(_ tint: FirstRunShowcase.Tint) -> Color {
    switch tint {
    case .salary: Color(hex: 0x12B76A)
    case .sideIncome: Color(hex: 0x32D583)
    case .housing: Color(hex: 0x2E90FA)
    case .food: Color(hex: 0xFF692E)
    case .shopping: Color(hex: 0xF23E94)
    case .transport: Color(hex: 0x875BF7)
    case .utilities: Color(hex: 0x06AED4)
    case .entertainment: Color(hex: 0xFDB022)
    case .surplus: Color(hex: 0x10A861)
    }
  }
}

private extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}
