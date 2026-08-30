import SwiftUI

struct SureLogo: View {
  var body: some View {
    Image("SureLogo")
      .resizable()
      .scaledToFit()
      .frame(width: 88, height: 88)
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .accessibilityElement(children: .ignore)
    .accessibilityLabel("Sure")
  }
}
