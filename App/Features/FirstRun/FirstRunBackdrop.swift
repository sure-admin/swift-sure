import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Full-bleed calm lake behind the pitches, darkened toward the copy.
///
/// Add a portrait photo (1290 × 2796 or larger) to the asset catalog as
/// `FirstRunBackdrop` to replace the drawn fallback scene. The design used
/// Moraine Lake (Wikimedia Commons, public domain); bundle a copy rather than
/// loading it remotely.
struct FirstRunBackdrop: View {
  static let assetName = "FirstRunBackdrop"

  var body: some View {
    ZStack {
      if Self.hasPhoto {
        Image(Self.assetName)
          .resizable()
          .scaledToFill()
      } else {
        FirstRunDrawnLake()
      }
      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.28), location: 0),
          .init(color: .black.opacity(0), location: 0.18),
          .init(color: .black.opacity(0), location: 0.42),
          .init(color: .black.opacity(0.55), location: 0.66),
          .init(color: .black.opacity(0.82), location: 1)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .accessibilityHidden(true)
  }

  private static let hasPhoto: Bool = {
    #if canImport(UIKit)
    return UIImage(named: assetName) != nil
    #elseif canImport(AppKit)
    return NSImage(named: assetName) != nil
    #else
    return false
    #endif
  }()
}

/// Stylized dawn lake used until a photo asset is bundled.
private struct FirstRunDrawnLake: View {
  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let shore = size.height * 0.52
      ZStack(alignment: .topLeading) {
        LinearGradient(
          colors: [Color(red: 0.55, green: 0.72, blue: 0.84), Color(red: 0.86, green: 0.9, blue: 0.88)],
          startPoint: .top,
          endPoint: UnitPoint(x: 0.5, y: 0.52)
        )
        ridge(size: size, base: shore, peaks: [0.0: 0.2, 0.18: 0.3, 0.35: 0.22, 0.55: 0.36, 0.78: 0.26, 1.0: 0.32])
          .fill(Color(red: 0.42, green: 0.5, blue: 0.58))
        ridge(size: size, base: shore, peaks: [0.0: 0.4, 0.25: 0.46, 0.5: 0.42, 0.72: 0.48, 1.0: 0.43])
          .fill(Color(red: 0.13, green: 0.25, blue: 0.24))
        LinearGradient(
          colors: [Color(red: 0.16, green: 0.52, blue: 0.56), Color(red: 0.04, green: 0.2, blue: 0.24)],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: size.height - shore)
        .offset(y: shore)
      }
    }
    .ignoresSafeArea()
  }

  /// A jagged skyline; `peaks` maps horizontal fraction to peak height as a
  /// fraction of the screen, measured from the top.
  private func ridge(size: CGSize, base: CGFloat, peaks: [CGFloat: CGFloat]) -> Path {
    Path { path in
      path.move(to: CGPoint(x: 0, y: base))
      for (x, y) in peaks.sorted(by: { $0.key < $1.key }) {
        path.addLine(to: CGPoint(x: x * size.width, y: y * size.height))
      }
      path.addLine(to: CGPoint(x: size.width, y: base))
      path.closeSubpath()
    }
  }
}
