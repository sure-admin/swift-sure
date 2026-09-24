import SwiftUI

/// Full-bleed Moraine Lake photograph, darkened toward the pitch copy.
struct FirstRunBackdrop: View {
  var body: some View {
    ZStack {
      Image("FirstRunBackdrop")
        .resizable()
        .scaledToFill()
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
}
