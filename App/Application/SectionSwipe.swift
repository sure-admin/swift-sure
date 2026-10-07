import CoreGraphics

/// Geometry for a horizontal swipe between top-level sections. `TabView` never
/// animates a selection change, so the app moves the content itself: the
/// selected section follows the finger, and the destination slides in from
/// where it would sit in a paged layout.
struct SectionSwipe: Equatable {
  /// Share of a drag past the first or last section that the content follows.
  static let edgeResistance: CGFloat = 0.3

  var translation: CGSize
  var predictedEndTranslation: CGSize

  /// Whether the drag reads as a sideways swipe rather than a vertical scroll.
  var isHorizontal: Bool {
    abs(translation.width) > abs(translation.height) * 1.25
  }

  /// How far the selected section's content follows the finger, resisting
  /// when there is no section to move to.
  func dragOffset(from section: AppSection) -> CGFloat {
    let direction = translation.width < 0 ? 1 : -1
    let hasNeighbor = section.moving(by: direction) != section
    return hasNeighbor ? translation.width : translation.width * Self.edgeResistance
  }

  /// The section a released drag selects, or nil when the content should settle back.
  func destination(from section: AppSection) -> AppSection? {
    let horizontalDistance = predictedEndTranslation.width
    let verticalDistance = predictedEndTranslation.height
    guard abs(horizontalDistance) > 60,
          abs(horizontalDistance) > abs(verticalDistance) * 1.25 else {
      return nil
    }

    let destination = section.moving(by: horizontalDistance < 0 ? 1 : -1)
    return destination == section ? nil : destination
  }

  /// Where the destination's content starts so it continues the finger's
  /// motion: one container width beyond the dragged content, on the side it
  /// enters from. A flick against the drag starts a full width away.
  func arrivalOffset(entering destination: AppSection, from section: AppSection, width: CGFloat) -> CGFloat {
    if destination.rawValue > section.rawValue {
      return width + min(max(translation.width, -width), 0)
    }
    return -width + max(min(translation.width, width), 0)
  }
}
