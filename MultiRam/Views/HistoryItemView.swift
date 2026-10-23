import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator
  var previous: HistoryItemDecorator?
  var next: HistoryItemDecorator?
  var index: Int

  private var visualIndex: Int? {
    if appState.navigator.isMultiSelectInProgress && item.selectionIndex >= 0 {
      return item.selectionIndex
    }
    return nil
  }

  private var selectionAppearance: SelectionAppearance {
    let previousSelected = previous?.isSelected ?? false
    let nextSelected = next?.isSelected ?? false
    switch (previousSelected, nextSelected) {
    case (true, false):
      return .topConnection
    case (false, true):
      return .bottomConnection
    case (true, true):
      return .topBottomConnection
    default:
      return .none
    }
  }

  @Environment(AppState.self) private var appState

  var body: some View {
    ListItemView(
      id: item.id,
      selectionId: item.id,
      appIcon: item.applicationImage,
      image: item.thumbnailImage,
      accessoryImage: item.thumbnailImage != nil ? nil : ColorImage.from(item.title),
      attributedTitle: item.attributedTitle,
      shortcuts: [],
      isSelected: item.isSelected,
      selectionIndex: visualIndex,
      selectionAppearance: selectionAppearance,
      isPinned: item.isPinned,
      onTogglePin: {
        withAnimation {
          appState.history.togglePin(item)
        }
      },
      canExpand: item.hasExpandableContent,
      isExpanded: appState.popup.detailItem === item,
      onToggleExpand: {
        appState.popup.toggleDetail(for: item)
      },
      onSelect: select
    ) {
      Text(verbatim: item.title)
    }
    .overlay(alignment: .bottom) {
      if next != nil {
        Divider()
          .padding(.horizontal, 10)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    .onAppear {
      item.ensureThumbnailImage()
    }
  }

  private func select() {
    if NSEvent.modifierFlags.contains(.command) && appState.multiSelectionEnabled {
      appState.navigator.addToSelection(item: item)
    } else {
      Task {
        appState.history.select(item)
      }
    }
  }
}
