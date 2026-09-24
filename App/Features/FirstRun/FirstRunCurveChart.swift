import SwiftUI

/// Cumulative spending artwork: this month (green) over last month (gray).
/// `progress` draws the lines in; the area and end marker fade in after.
struct FirstRunCurveChart: View {
  var curve: FirstRunShowcase.Curve
  var currency: CurrencyCode
  var progress: Double
  var showsScale = true

  private static let scaleWidth: CGFloat = 40
  private static let topInset: CGFloat = 8

  var body: some View {
    GeometryReader { proxy in
      let plot = CGSize(
        width: proxy.size.width - (showsScale ? Self.scaleWidth : 0),
        height: proxy.size.height - Self.topInset
      )
      let geometry = Geometry(curve: curve, size: plot, topInset: Self.topInset)
      ZStack(alignment: .topLeading) {
        ForEach(geometry.ticks, id: \.self) { tick in
          Path { path in
            path.move(to: CGPoint(x: 0, y: geometry.y(tick)))
            path.addLine(to: CGPoint(x: plot.width, y: geometry.y(tick)))
          }
          .stroke(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
          if showsScale {
            Text(FinanceFormatters.compactCurrency(DecimalMoney(amount: Decimal(tick), currency: currency)))
              .font(.system(size: 10).monospacedDigit())
              .foregroundStyle(FirstRunPalette.chartLabel)
              .frame(width: Self.scaleWidth, alignment: .trailing)
              .position(x: proxy.size.width - Self.scaleWidth / 2, y: geometry.y(tick))
          }
        }
        FirstRunSmoothLine(points: geometry.points(curve.previous))
          .trim(from: 0, to: progress)
          .stroke(FirstRunPalette.previousLine, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
        FirstRunSmoothLine(points: geometry.points(curve.current), closingBaseline: geometry.y(0))
          .fill(FirstRunPalette.green.opacity(0.08))
          .opacity(progress >= 1 ? 1 : 0)
        FirstRunSmoothLine(points: geometry.points(curve.current))
          .trim(from: 0, to: progress)
          .stroke(FirstRunPalette.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        if let last = geometry.points(curve.current).last {
          Circle()
            .fill(FirstRunPalette.green)
            .overlay { Circle().stroke(.white, lineWidth: 2) }
            .frame(width: 10, height: 10)
            .position(last)
            .opacity(progress >= 1 ? 1 : 0)
        }
      }
    }
    .accessibilityHidden(true)
  }

  private struct Geometry {
    var curve: FirstRunShowcase.Curve
    var size: CGSize
    var topInset: CGFloat
    var maxValue: Double

    init(curve: FirstRunShowcase.Curve, size: CGSize, topInset: CGFloat) {
      self.curve = curve
      self.size = size
      self.topInset = topInset
      maxValue = max(curve.previous.last ?? 1, curve.current.last ?? 1, 1) * 1.08
    }

    /// Roughly three gridlines at 1/2/2.5/5 × 10ⁿ steps, matching Sure's charts.
    var ticks: [Double] {
      let raw = maxValue / 3
      let magnitude = pow(10, floor(log10(raw)))
      let step = [1, 2, 2.5, 5, 10].map { $0 * magnitude }.first { $0 >= raw } ?? raw
      return Array(stride(from: step, to: maxValue, by: step))
    }

    func y(_ value: Double) -> CGFloat {
      topInset + size.height - CGFloat(value / maxValue) * size.height
    }

    func points(_ values: [Double]) -> [CGPoint] {
      let span = CGFloat(max(curve.dayCount - 1, 1))
      return values.enumerated().map { index, value in
        CGPoint(x: CGFloat(index) / span * size.width, y: y(value))
      }
    }
  }
}

/// Catmull-Rom smoothing through every point, optionally closed to a baseline.
struct FirstRunSmoothLine: Shape {
  var points: [CGPoint]
  var closingBaseline: CGFloat?

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard let first = points.first, points.count > 1 else { return path }
    path.move(to: first)
    let tension: CGFloat = 0.18
    for index in 0..<(points.count - 1) {
      let p0 = points[max(index - 1, 0)]
      let p1 = points[index]
      let p2 = points[index + 1]
      let p3 = points[min(index + 2, points.count - 1)]
      // Clamp control points vertically so a rising cumulative line never dips.
      let low = min(p1.y, p2.y), high = max(p1.y, p2.y)
      let control1 = CGPoint(x: p1.x + (p2.x - p0.x) * tension, y: min(max(p1.y + (p2.y - p0.y) * tension, low), high))
      let control2 = CGPoint(x: p2.x - (p3.x - p1.x) * tension, y: min(max(p2.y - (p3.y - p1.y) * tension, low), high))
      path.addCurve(to: p2, control1: control1, control2: control2)
    }
    if let closingBaseline, let last = points.last {
      path.addLine(to: CGPoint(x: last.x, y: closingBaseline))
      path.addLine(to: CGPoint(x: first.x, y: closingBaseline))
      path.closeSubpath()
    }
    return path
  }
}
