import CoreGraphics
import Testing
@testable import Sure

@Suite("Section swipe")
struct SectionSwipeTests {
  @Test("Commits a horizontal swipe to the adjacent section")
  func commitsHorizontalSwipe() {
    let left = SectionSwipe(translation: CGSize(width: -80, height: 4),
      predictedEndTranslation: CGSize(width: -200, height: 10))
    let right = SectionSwipe(translation: CGSize(width: 80, height: 4),
      predictedEndTranslation: CGSize(width: 200, height: 10))

    #expect(left.destination(from: .overview) == .assistant)
    #expect(right.destination(from: .accounts) == .assistant)
  }

  @Test("Settles back for short, vertical, or edge swipes")
  func settlesBack() {
    let short = SectionSwipe(translation: CGSize(width: -30, height: 0),
      predictedEndTranslation: CGSize(width: -50, height: 0))
    let vertical = SectionSwipe(translation: CGSize(width: -60, height: -90),
      predictedEndTranslation: CGSize(width: -120, height: -300))
    let pastEnd = SectionSwipe(translation: CGSize(width: -80, height: 0),
      predictedEndTranslation: CGSize(width: -200, height: 0))

    #expect(short.destination(from: .overview) == nil)
    #expect(vertical.destination(from: .overview) == nil)
    #expect(pastEnd.destination(from: .budget) == nil)
  }

  @Test("Follows the finger, resisting past the first and last sections")
  func dragOffset() {
    let left = SectionSwipe(translation: CGSize(width: -100, height: 0), predictedEndTranslation: .zero)
    let right = SectionSwipe(translation: CGSize(width: 100, height: 0), predictedEndTranslation: .zero)

    #expect(left.dragOffset(from: .overview) == -100)
    #expect(right.dragOffset(from: .budget) == 100)
    #expect(right.dragOffset(from: .overview) == 100 * SectionSwipe.edgeResistance)
    #expect(left.dragOffset(from: .budget) == -100 * SectionSwipe.edgeResistance)
  }

  @Test("Distinguishes sideways swipes from vertical scrolls")
  func axis() {
    #expect(SectionSwipe(translation: CGSize(width: 40, height: 10), predictedEndTranslation: .zero).isHorizontal)
    #expect(!SectionSwipe(translation: CGSize(width: 10, height: 40), predictedEndTranslation: .zero).isHorizontal)
  }

  @Test("The destination enters beside the dragged content")
  func arrivalOffset() {
    let left = SectionSwipe(translation: CGSize(width: -120, height: 0), predictedEndTranslation: .zero)
    let right = SectionSwipe(translation: CGSize(width: 120, height: 0), predictedEndTranslation: .zero)

    #expect(left.arrivalOffset(entering: .assistant, from: .overview, width: 400) == 280)
    #expect(right.arrivalOffset(entering: .accounts, from: .budget, width: 400) == -280)
  }

  @Test("A flick against the drag enters from a full width away")
  func arrivalOffsetBounds() {
    let backtracked = SectionSwipe(translation: CGSize(width: 30, height: 0), predictedEndTranslation: .zero)
    let overshot = SectionSwipe(translation: CGSize(width: -600, height: 0), predictedEndTranslation: .zero)

    #expect(backtracked.arrivalOffset(entering: .assistant, from: .overview, width: 400) == 400)
    #expect(overshot.arrivalOffset(entering: .assistant, from: .overview, width: 400) == 0)
  }
}
