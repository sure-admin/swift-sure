import SwiftUI

/// A white "screenshot" card with a deep green drop shadow and a periodic sheen.
struct FirstRunGlossCard<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var cornerRadius: CGFloat = 18
  var padding: CGFloat = 14
  var sheenDelay: Double = 0
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(padding)
      .background(.white)
      .overlay {
        if !reduceMotion { FirstRunSheen(delay: sheenDelay) }
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(Color.black.opacity(0.05))
      }
      .shadow(color: FirstRunPalette.glow.opacity(0.38), radius: 30, y: 30)
      .shadow(color: .black.opacity(0.18), radius: 12, y: 12)
      .environment(\.colorScheme, .light)
  }
}

/// A diagonal highlight that crosses the card every six seconds.
private struct FirstRunSheen: View {
  var delay: Double
  @State private var start = Date.now

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
      let elapsed = timeline.date.timeIntervalSince(start) - 1.8 - delay
      // Sweeps right to left over the first 2.1 s of each 6 s cycle, then rests.
      let cycle = elapsed < 0 ? 0 : elapsed.truncatingRemainder(dividingBy: 6) / 2.1
      GeometryReader { proxy in
        let width = proxy.size.width
        let highlightX = width * 1.6 - width * 2.2 * min(max(cycle, 0), 1)
        LinearGradient(
          stops: [
            .init(color: .white.opacity(0), location: 0.38),
            .init(color: .white.opacity(0.8), location: 0.5),
            .init(color: .white.opacity(0), location: 0.62)
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
        .rotationEffect(.degrees(20))
        .frame(width: width * 3, height: proxy.size.height)
        .offset(x: highlightX - width * 1.5)
        .opacity(elapsed < 0 || cycle >= 1 ? 0 : 1)
      }
    }
    .allowsHitTesting(false)
  }
}
