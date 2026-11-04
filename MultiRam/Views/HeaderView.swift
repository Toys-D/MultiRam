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
    VStack(alignment: .leading, spacing: 6) {
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

      HistoryFilterBar()
        .padding(.horizontal, Popup.horizontalPadding)
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

// Narrows the list to text, images or files.
struct HistoryFilterBar: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    HStack(spacing: 4) {
      ForEach(HistoryFilter.allCases) { filter in
        let selected = appState.history.filter == filter
        Button {
          appState.history.filter = filter
        } label: {
          Label(filter.title, systemImage: filter.symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.07), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history-filter-\(filter.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
      Spacer(minLength: 0)
    }
  }
}
