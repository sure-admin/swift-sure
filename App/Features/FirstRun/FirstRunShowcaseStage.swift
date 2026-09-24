import SwiftUI

/// Floating, tilted stack of glossy chart cards behind a pitch. Laid out on the
/// design's 402 × 400 pt canvas and scaled to the available width.
struct FirstRunShowcaseStage: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var kind: FirstRunPitch.Kind
  var showcase: FirstRunShowcase
  var configuration: FirstRunConfiguration

  @State private var entered = false
  @State private var floating = false
  @State private var drawn = false

  static let canvas = CGSize(width: 402, height: 400)

  var body: some View {
    GeometryReader { proxy in
      let scale = min(proxy.size.width / Self.canvas.width, 1.4)
      ZStack {
        RadialGradient(
          colors: [Color(red: 0.65, green: 0.96, blue: 0.77).opacity(0.9), .clear],
          center: UnitPoint(x: 0.55, y: 0.5),
          startRadius: 0,
          endRadius: 220
        )
        .scaleEffect(x: 1.3, y: 1)
        .padding(-40)
        Ellipse()
          .fill(FirstRunPalette.glow.opacity(0.22))
          .frame(width: 290, height: 36)
          .blur(radius: 22)
          .offset(x: 16, y: 142)
        cards
          .rotation3DEffect(.degrees(entered ? 5 : -2), axis: (x: 0, y: 0, z: 1))
          .rotation3DEffect(.degrees(entered ? -16 : -2), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
          .rotation3DEffect(.degrees(entered ? 22 : 50), axis: (x: 1, y: 0, z: 0), anchor: UnitPoint(x: 0.5, y: 0.75), perspective: 0.4)
          .scaleEffect(entered ? 1 : 0.85)
          .offset(y: entered ? 0 : 60)
          .opacity(entered ? 1 : 0)
          .rotationEffect(.degrees(floating ? -1 : 0))
          .offset(y: floating ? -6 : 0)
      }
      .frame(width: Self.canvas.width, height: Self.canvas.height)
      .scaleEffect(scale, anchor: .top)
      .frame(width: proxy.size.width, height: Self.canvas.height * scale, alignment: .top)
    }
    .frame(height: Self.canvas.height)
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(kind == .wallet
      ? Text("Illustration of a Wallet spending comparison")
      : Text("Illustration of Sure’s cash flow and spending charts"))
    .onAppear(perform: animateIn)
  }

  private func animateIn() {
    guard !reduceMotion else {
      entered = true
      drawn = true
      return
    }
    withAnimation(.spring(duration: 1.7, bounce: 0)) { entered = true }
    withAnimation(.easeOut(duration: 1.6).delay(0.35)) { drawn = true }
    withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true).delay(1.7)) { floating = true }
  }

  private var cards: some View {
    ZStack(alignment: .topLeading) {
      switch kind {
      case .demo:
        FirstRunGlossCard {
          VStack(alignment: .leading, spacing: 12) {
            header(Text("Cash flow"), trailing: Text(configuration.previousMonth))
            FirstRunSankey(showcase: showcase, progress: drawn ? 1 : 0)
              .frame(width: 278, height: 210)
          }
        }
        .frame(width: 306)
        .offset(x: 40, y: 4)

        FirstRunGlossCard(sheenDelay: 0.6) {
          VStack(alignment: .leading, spacing: 2) {
            Text("\(configuration.currentMonth) so far")
              .font(.system(size: 11))
              .foregroundStyle(FirstRunPalette.chartLabel)
            Text(FinanceFormatters.currency(DecimalMoney(amount: showcase.demoCurve.currentTotal, currency: showcase.currency)))
              .font(.system(size: 17, weight: .medium).monospacedDigit())
              .padding(.bottom, 4)
            FirstRunCurveChart(curve: showcase.demoCurve, currency: showcase.currency, progress: drawn ? 1 : 0)
              .frame(height: 70)
          }
        }
        .frame(width: 204)
        .scaleEffect(1.04)
        .offset(x: 128, y: 190)

        deltaPill(showcase.demoCurve.delta)
          .offset(x: 48, y: 262)
      case .wallet:
        FirstRunGlossCard {
          VStack(alignment: .leading, spacing: 2) {
            header(Text("\(configuration.currentMonth) spending"), trailing: Text("Days 1–\(showcase.walletCurve.elapsedDays)"))
            Text(FinanceFormatters.currency(DecimalMoney(amount: showcase.walletCurve.currentTotal, currency: showcase.currency)))
              .font(.system(size: 22, weight: .medium).monospacedDigit())
              .tracking(-0.5)
              .padding(.bottom, 8)
            FirstRunCurveChart(curve: showcase.walletCurve, currency: showcase.currency, progress: drawn ? 1 : 0)
              .frame(height: 150)
          }
        }
        .frame(width: 290)
        .offset(x: 52, y: 8)

        FirstRunGlossCard(sheenDelay: 0.6) {
          VStack(alignment: .leading, spacing: 0) {
            Text("Accounts on this iPhone")
              .font(.system(size: 11))
              .foregroundStyle(FirstRunPalette.chartLabel)
              .padding(.bottom, 6)
            ForEach(Array(showcase.walletAccounts.prefix(2).enumerated()), id: \.offset) { index, name in
              if index > 0 { Divider().opacity(0.4) }
              HStack(spacing: 8) {
                Text(name.prefix(1))
                  .font(.system(size: 10, weight: .semibold))
                  .frame(width: 22, height: 22)
                  .background(index == 0 ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1), in: Circle())
                  .foregroundStyle(index == 0 ? Color.blue : Color.orange)
                Text(name)
                  .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                  .font(.system(size: 11, weight: .bold))
                  .foregroundStyle(FirstRunPalette.green)
              }
              .padding(.vertical, 5)
            }
          }
        }
        .frame(width: 200)
        .scaleEffect(1.04)
        .offset(x: 18, y: 196)

        deltaPill(showcase.walletCurve.delta)
          .offset(x: 196, y: 214)
      }
    }
    .foregroundStyle(FirstRunPalette.chartInk)
    .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
  }

  private func header(_ title: Text, trailing: Text) -> some View {
    HStack(alignment: .firstTextBaseline) {
      title.font(.system(size: 12, weight: .medium))
      Spacer()
      trailing.font(.system(size: 10)).foregroundStyle(FirstRunPalette.chartLabel)
    }
  }

  private func deltaPill(_ delta: Decimal) -> some View {
    FirstRunGlossCard(cornerRadius: 19, padding: 0, sheenDelay: 1.2) {
      Label {
        Text(delta >= 0 ? "\(money(delta)) less" : "\(money(-delta)) more")
      } icon: {
        Image(systemName: delta >= 0 ? "arrow.down" : "arrow.up")
      }
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(delta >= 0 ? FirstRunPalette.greenDark : Color.red)
      .padding(.horizontal, 14)
      .frame(height: 38)
      .fixedSize()
    }
  }

  private func money(_ amount: Decimal) -> String {
    FinanceFormatters.wholeCurrency(DecimalMoney(amount: amount, currency: showcase.currency))
  }
}
