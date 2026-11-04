import AppKit
import Defaults
import Foundation
import SwiftUI

@Observable
final class AppState {
  static let shared = AppState(history: History.shared, footer: Footer())

  let multiSelectionEnabled = true

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer
  var navigator: NavigationManager

  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  @ObservationIgnored @MainActor private lazy var settingsWindow = SettingsWindowPresenter()

  init(history: History, footer: Footer) {
    self.history = history
    self.footer = footer
    popup = Popup()
    navigator = NavigationManager(history: history, footer: footer)
  }

  @MainActor
  func select() {
    if !navigator.selection.isEmpty {
      navigator.isManualMultiSelect = false
      if navigator.selection.count > 1 {
        history.pasteMerged(navigator.selection.items)
      } else {
        history.select(navigator.selection.first)
      }
    } else if let item = footer.selectedItem {
      // TODO: Use item.suppressConfirmation, but it's not updated!
      if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  @MainActor
  func togglePin() {
    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.togglePin(item)
      }
    }
  }

  @MainActor
  func removePasteStack() {
    history.interruptPasteStack()
    navigator.highlightFirst()
  }

  @MainActor
  func deleteSelection() {
    guard let leadItem = navigator.leadHistoryItem else { return }
    let nextUnselectedItem = history.visibleItems.nearest(to: leadItem) { !$0.isSelected }

    withTransaction(Transaction()) {
      var deleted = true
      navigator.selection.forEach { _, item in
        deleted = history.delete(item) && deleted
      }
      if deleted { navigator.select(item: nextUnselectedItem) }
    }
  }

  @MainActor
  func openAbout() {
    openPreferences(.about)
  }

  @MainActor
  func openPreferences(_ section: SettingsSection? = nil) {
    settingsWindow.show(section)
  }

  func quit() {
    NSApp.terminate(self)
  }
}
