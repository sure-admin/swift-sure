import SwiftUI

/// Launch hero shown before the first Wallet or Sure connection. The lake
/// stays put (with slight parallax) while pitches slide; the first pitch flips
/// to the second once after a delay, then the person can swipe between them.
struct FirstRunView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
  var store: FirstRunStore

  @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.4, bounce: 0)))
  private var dragOffset: CGFloat = 0
  /// Artwork mounts on first view so its entrance plays when the page arrives.
  @State private var seen: Set<FirstRunPitch.Kind> = []

  var body: some View {
    GeometryReader { proxy in
      let width = max(proxy.size.width, 1)
      let position = CGFloat(store.selectedIndex) - dragOffset / width
      ZStack(alignment: .bottom) {
        FirstRunBackdrop()
          .frame(width: proxy.size.width, height: proxy.size.height)
          .scaleEffect(1.08)
          .offset(x: reduceMotion ? 0 : -position * width * 0.03)
          .clipped()

        HStack(spacing: 0) {
          ForEach(store.pages) { pitch in
            FirstRunPitchPage(
              pitch: pitch,
              showcase: store.market.showcase,
              configuration: store.configuration,
              showsArtwork: seen.contains(pitch.kind),
              isBusy: store.isBusy && store.selectedPage.kind == pitch.kind,
              start: { Task { await store.start(pitch) } }
            )
            .frame(width: width)
            .opacity(store.isBusy && store.selectedPage.kind != pitch.kind ? 0 : 1)
            .accessibilityHidden(store.selectedPage.kind != pitch.kind)
          }
        }
        .frame(width: width, alignment: .leading)
        .offset(x: -CGFloat(store.selectedIndex) * width + dragOffset)
        .animation(dragOffset == 0 ? .spring(duration: 0.75, bounce: 0) : nil, value: store.selectedIndex)

        pageControl
          .padding(.bottom, 26)
          .opacity(store.isBusy ? 0 : 1)
      }
      .contentShape(Rectangle())
      .gesture(swipe(width: width), including: store.isBusy ? .none : .all)
    }
    .ignoresSafeArea()
    .background(FirstRunPalette.night)
    .preferredColorScheme(.dark)
    .sensoryFeedback(.selection, trigger: store.selectedIndex)
    .onAppear { seen.insert(store.selectedPage.kind) }
    .onChange(of: store.selectedIndex) { _, _ in seen.insert(store.selectedPage.kind) }
    .task {
      // Automatic page changes would interrupt VoiceOver mid-sentence.
      guard !voiceOverEnabled else { return }
      await store.runAutoAdvance()
    }
    #if DEBUG
    .overlay(alignment: .topTrailing) { FirstRunDesignMenu(store: store) }
    #endif
  }

  private var pageControl: some View {
    HStack(spacing: 6) {
      ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, pitch in
        let selected = index == store.selectedIndex
        Button {
          withAnimation(.spring(duration: 0.75, bounce: 0)) { store.select(index) }
        } label: {
          Capsule()
            .fill(.white.opacity(selected ? 1 : 0.4))
            .frame(width: selected ? 18 : 6, height: 6)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pitch.pageLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .animation(.spring(duration: 0.4), value: store.selectedIndex)
  }

  private func swipe(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .updating($dragOffset) { value, state, _ in
        var offset = value.translation.width
        let atStart = store.selectedIndex == 0 && offset > 0
        let atEnd = store.selectedIndex == store.pages.count - 1 && offset < 0
        if atStart || atEnd { offset *= 0.3 }
        state = offset
      }
      .onEnded { value in
        guard abs(value.translation.width) > 50 else { return }
        let target = store.selectedIndex + (value.translation.width < 0 ? 1 : -1)
        withAnimation(.spring(duration: 0.75, bounce: 0)) { store.select(target) }
      }
  }
}
