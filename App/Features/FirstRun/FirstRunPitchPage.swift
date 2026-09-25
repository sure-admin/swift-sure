import SwiftUI

/// One pitch: floating chart artwork behind a bottom-anchored headline,
/// body, and call to action.
struct FirstRunPitchPage: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var pitch: FirstRunPitch
  var showcase: FirstRunShowcase
  var configuration: FirstRunConfiguration
  var showsArtwork: Bool
  var isBusy: Bool
  var start: () -> Void

  @State private var risen = false

  var body: some View {
    // The artwork floats behind the copy, as in the design; on short screens
    // the darkened lower half of the backdrop keeps the copy legible.
    ZStack(alignment: .bottom) {
      if showsArtwork {
        FirstRunShowcaseStage(kind: pitch.kind, showcase: showcase, configuration: configuration)
          .padding(.top, 112)
          .frame(maxHeight: .infinity, alignment: .top)
      }
      copy
    }
    .onAppear { risen = true }
  }

  private var copy: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(pitch.title)
        .font(.largeTitle.weight(.medium))
        .tracking(-1.1)
        .minimumScaleFactor(0.7)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 2)
        .accessibilityAddTraits(.isHeader)
        .rise(risen, delay: 0, reduceMotion: reduceMotion)

      Text(pitch.body)
        .font(.callout)
        .foregroundStyle(.white.opacity(0.78))
        .padding(.bottom, 10)
        .rise(risen, delay: 0.08, reduceMotion: reduceMotion)

      VStack(spacing: 12) {
        Button(action: start) {
          HStack(spacing: 8) {
            if isBusy {
              ProgressView().tint(FirstRunPalette.chartInk)
            } else {
              Text(pitch.callToAction)
              Image(systemName: "arrow.right")
            }
          }
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 56)
          .contentShape(Rectangle())
        }
        .buttonStyle(FirstRunPrimaryButtonStyle())
        .disabled(isBusy)
        .accessibilityHint(pitch.action == .connectWallet
          ? Text(String(localized: "first_run.accessibility.share_wallet", table: "FirstRun"))
          : Text(String(localized: "first_run.accessibility.open_demo", table: "FirstRun")))

        Label(pitch.footnote, systemImage: pitch.footnoteSymbol)
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.65))
      }
      .frame(maxWidth: .infinity)
      .rise(risen, delay: 0.16, reduceMotion: reduceMotion)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 24)
    .padding(.bottom, 58)
  }
}

struct FirstRunPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(FirstRunPalette.chartInk)
      .background(
        configuration.isPressed ? Color(white: 0.94) : .white,
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.spring(duration: 0.2), value: configuration.isPressed)
  }
}

private extension View {
  /// Fades and lifts content into place, like the design's `fr-rise`.
  func rise(_ risen: Bool, delay: Double, reduceMotion: Bool) -> some View {
    opacity(risen ? 1 : 0)
      .offset(y: risen || reduceMotion ? 0 : 18)
      .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.9, bounce: 0).delay(delay), value: risen)
  }
}
