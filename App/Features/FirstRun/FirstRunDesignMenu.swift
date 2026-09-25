#if DEBUG
import SwiftUI

/// Debug-only switcher for comparing copy variants and regions in place.
/// Release builds can still choose them with launch arguments; see
/// `FirstRunPreferences`.
struct FirstRunDesignMenu: View {
  var store: FirstRunStore

  var body: some View {
    Menu {
      Picker(String(localized: "first_run.design.copy", table: "FirstRun"), selection: Binding(
        get: { store.configuration.variant },
        set: { store.apply(variant: $0) }
      )) {
        ForEach(FirstRunCopyVariant.allCases, id: \.self) { variant in
          Text(variant.displayName).tag(variant)
        }
      }
      Picker(String(localized: "first_run.design.region", table: "FirstRun"), selection: Binding(
        get: { store.configuration.region },
        set: { store.apply(region: $0) }
      )) {
        ForEach(FirstRunRegion.allCases, id: \.self) { region in
          Text(region.displayName).tag(region)
        }
      }
    } label: {
      Image(systemName: "slider.horizontal.3")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 32, height: 32)
        .background(.white.opacity(0.14), in: Circle())
    }
    .accessibilityLabel(String(localized: "first_run.design.options", table: "FirstRun"))
    .padding(.trailing, 16)
    .padding(.top, 8)
  }
}
#endif
