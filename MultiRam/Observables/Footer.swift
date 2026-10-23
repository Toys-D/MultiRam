import Defaults
import SwiftUI

@Observable
class Footer: ItemsContainer {
  var items: [FooterItem] = []

  var selectedItem: FooterItem? {
    willSet {
      selectedItem?.isSelected = false
      newValue?.isSelected = true
    }
  }

  var suppressClearAlert = Binding<Bool>(
    get: { Defaults[.suppressClearAlert] },
    set: { Defaults[.suppressClearAlert] = $0 }
  )

  var containerVisible: Bool {
    // These commands live in the toolbar, outside history keyboard navigation.
    return false
  }

  init() { // swiftlint:disable:this function_body_length
    items = [
      FooterItem(
        title: "clear",
        shortcuts: [KeyShortcut(key: .delete, modifierFlags: [.command, .option])],
        help: "clear_tooltip",
        confirmation: .init(
          message: "clear_alert_message",
          comment: "clear_alert_comment",
          confirm: "clear_alert_confirm",
          cancel: "clear_alert_cancel"
        ),
        suppressConfirmation: suppressClearAlert
      ) {
        Task { @MainActor in
          AppState.shared.history.clear()
        }
      },
      FooterItem(
        title: "clear_all",
        shortcuts: [KeyShortcut(key: .delete, modifierFlags: [.command, .option, .shift])],
        help: "clear_all_tooltip",
        confirmation: .init(
          message: "clear_alert_message",
          comment: "clear_alert_comment",
          confirm: "clear_alert_confirm",
          cancel: "clear_alert_cancel"
        ),
        suppressConfirmation: suppressClearAlert
      ) {
        Task { @MainActor in
          AppState.shared.history.clearAll()
        }
      }
    ]
    items[1].isVisible = false
  }
}
