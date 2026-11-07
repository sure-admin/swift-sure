import SwiftUI

struct TabSwipeNavigationModifier: ViewModifier {
  var moveSelection: (Int) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var excludedFrames: [UUID: CGRect] = [:]
  @State private var startedInExcludedRegion = false

  func body(content: Content) -> some View {
    content
      .environment(\.registerTabSwipeExclusion) { id, frame in excludedFrames[id] = frame }
      .simultaneousGesture(
        DragGesture(minimumDistance: 24, coordinateSpace: .global)
          .onChanged { value in
            // Capture before a successful dismissal can remove the originating row.
            startedInExcludedRegion = excludedFrames.values.contains { $0.contains(value.startLocation) }
          }
          .onEnded { value in
            guard !startedInExcludedRegion else { return }
            let horizontal = value.predictedEndTranslation.width
            let vertical = value.predictedEndTranslation.height
            guard abs(horizontal) > 60, abs(horizontal) > abs(vertical) * 1.25 else { return }
            withAnimation(reduceMotion ? nil : .snappy) {
              moveSelection(horizontal < 0 ? 1 : -1)
            }
          }
      )
  }

}

private struct TabSwipeExclusionModifier: ViewModifier {
  @Environment(\.registerTabSwipeExclusion) private var register
  @State private var id = UUID()

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { register(id, $0) }
      .onDisappear { register(id, nil) }
  }
}

private extension EnvironmentValues {
  @Entry var registerTabSwipeExclusion: (UUID, CGRect?) -> Void = { _, _ in }
}

extension View {
  func excludingTabSwipes() -> some View {
    modifier(TabSwipeExclusionModifier())
  }
}
