import SwiftUI

struct SureLogo: View {
  var body: some View {
    VStack(alignment: .leading, spacing: -16) {
      Text("su")
        .foregroundStyle(.secondary)
      Text("re")
        .foregroundStyle(SureTheme.accent)
    }
    .font(.system(size: 52, weight: .black, design: .rounded))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Sure")
  }
}
