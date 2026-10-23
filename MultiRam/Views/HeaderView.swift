import Defaults
import SwiftUI

struct HeaderView: View {
  @State private var appState = AppState.shared
  @Environment(ModifierFlags.self) private var modifierFlags

  @FocusState.Binding var searchFocused: Bool

  private var clearItem: FooterItem {
    appState.footer.items[modifierFlags.flags.contains(.shift) ? 1 : 0]
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      HStack(alignment: .center, spacing: 0) {
        ListHeaderView(
          searchFocused: $searchFocused,
          searchQuery: $appState.history.searchQuery
        )
        .padding(.horizontal, Popup.horizontalPadding)
        .opacity(appState.searchVisible ? 1 : 0)
        .accessibilityHidden(!appState.searchVisible)

        ToolbarButton {
          clearItem.perform()
        } label: {
          Image(systemName: "trash")
        }
        .accessibilityIdentifier("clear-history")
        .accessibilityLabel(Text(LocalizedStringKey(clearItem.title)))
        .help(Text(clearItem.help ?? "clear_tooltip"))
        .padding(.trailing, Popup.horizontalPadding)

      }
      .layoutPriority(1)
    }
    .padding(.top, Popup.verticalPadding)
    .padding(.horizontal, 10)
    .animation(.default.speed(3), value: appState.navigator.leadSelection)
    .background(.clear)
    .readHeight(appState, into: \.popup.headerHeight)
    .modifier(ConfirmationModifier(item: appState.footer.items[0]))
    .modifier(ConfirmationModifier(item: appState.footer.items[1]))
  }
}
