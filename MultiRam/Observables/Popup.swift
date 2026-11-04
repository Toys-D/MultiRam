import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

enum PopupState {
  // Default; shortcut will toggle the popup
  case toggle
  // In this mode, every additional press of the main key
  // will cycle to the next item in the paste history list.
  // Releasing the modifier keys will accept selection and close the popup
  case cycle
  // Transition state when the shortcut is first pressed and
  // we don't know whether we are in "toggle" or "cycle" mode.
  case opening
}

@Observable
class Popup {
  static let verticalSeparatorPadding = 6.0
  static let horizontalSeparatorPadding = 6.0
  static let verticalPadding: CGFloat = 5
  static let horizontalPadding: CGFloat = 5
  static let minimumWindowWidth: CGFloat = 200
  static let minimumWindowHeight: CGFloat = 150
  static let textDetailWidth: CGFloat = 560
  static let minimumDetailWidth: CGFloat = 320
  static let detailPadding: CGFloat = 12
  // Divider and the row of Open With buttons under an image.
  static let detailActionBarHeight: CGFloat = 44
  private static let detailLineHeight: CGFloat = 18
  private static let detailCharactersPerLine = 70

  // Radius used for items inset by the padding. Ensures they visually have the same curvature
  // as the menu.
  static let cornerRadius: CGFloat = if #available(macOS 26.0, *) {
    7
  } else {
    4
  }

  static let itemHeight: CGFloat = if #available(macOS 26.0, *) {
    24
  } else {
    22
  }

  var needsResize = false
  var height: CGFloat = 0
  var headerHeight: CGFloat = 0
  var extraTopHeight: CGFloat = 0
  var extraBottomHeight: CGFloat = 0
  var footerHeight: CGFloat = 0

  // The item shown in the side panel; nil while the panel is closed.
  var detailItem: HistoryItemDecorator?
  var detailWidth: CGFloat = 0
  var detailSide: DetailPanelSide = .trailing
  private var detailPreferredHeight: CGFloat = 0

  private var eventsMonitor: Any?

  private var state: PopupState = .toggle

  init() {
    KeyboardShortcuts.onKeyDown(for: .popup, action: handleFirstKeyDown)
    KeyboardShortcuts.onKeyDown(for: .popupFallback, action: handleFallbackKeyDown)
    Self.resolveShortcutConflict()
    initEventsMonitor()
  }

  deinit {
    deinitEventsMonitor()
  }

  func initEventsMonitor() {
    guard eventsMonitor == nil else { return }

    self.eventsMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.flagsChanged, .keyDown],
      handler: handleEvent
    )
  }

  var hasEventsMonitor: Bool { eventsMonitor != nil }

  func deinitEventsMonitor() {
    guard let eventsMonitor else { return }

    NSEvent.removeMonitor(eventsMonitor)
    // Forget the removed monitor so initEventsMonitor() can install a new one.
    self.eventsMonitor = nil
  }

  // Equal main and fallback shortcuts share one Carbon hot key, so one press would run both handlers
  // and open and close the popup at once. The main shortcut wins and the fallback is cleared.
  @discardableResult
  static func resolveShortcutConflict() -> Bool {
    guard let fallback = KeyboardShortcuts.getShortcut(for: .popupFallback),
          fallback == KeyboardShortcuts.getShortcut(for: .popup) else {
      return false
    }
    KeyboardShortcuts.setShortcut(nil, for: .popupFallback)
    // Clearing unregisters the shared hot key, which the main shortcut still needs.
    KeyboardShortcuts.enable(.popup)
    return true
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func reset() {
    state = .toggle
    AppState.shared.history.filter = .all
    KeyboardShortcuts.enable(.popup, .popupFallback)
    // Reopen with the list only and free the large image of the previous session.
    let item = detailItem
    detailItem = nil
    detailWidth = 0
    detailPreferredHeight = 0
    Task { @MainActor in
      item?.releaseExpandedContent()
    }
    // Applications may be installed or removed before the next time the popup opens.
    ImageEditorCatalog.shared.invalidate()
  }

  func close() {
    AppState.shared.appDelegate?.panel.close()  // close() calls reset
  }

  func isClosed() -> Bool {
    AppState.shared.appDelegate?.panel.isPresented != true
  }

  func preferredHeight(for newHeight: CGFloat) -> CGFloat {
    var height = max(newHeight, detailPreferredHeight)

    let minimumHeight = headerHeight + Self.verticalPadding
    height = max(height, minimumHeight)
    height = min(height, Self.maximumHeight(for: Defaults[.windowSize].height))
    return height
  }

  static func maximumHeight(for savedHeight: CGFloat) -> CGFloat {
    // Older versions saved automatic content sizes as the user's height limit,
    // including the nearly empty list during startup. Recover those collapsed limits.
    guard savedHeight.isFinite, savedHeight >= minimumWindowHeight else {
      return Defaults.Keys.windowSize.defaultValue.height
    }
    return savedHeight
  }

  // Width of the side panel: text uses a fixed width, images follow their aspect ratio at the panel
  // height without upscaling. Both stay within half of the screen.
  static func detailWidth(imageSize: NSSize?, panelHeight: CGFloat, screenWidth: CGFloat) -> CGFloat {
    let padding = detailPadding * 2
    let maximum = max(minimumDetailWidth, (screenWidth / 2).rounded(.down))
    var width = textDetailWidth
    if let imageSize, imageSize.height > 0 {
      let availableHeight = max(1, panelHeight - padding - detailActionBarHeight)
      let scale = min(1, availableHeight / imageSize.height)
      width = (imageSize.width * scale).rounded() + padding
    }
    return min(max(width, minimumDetailWidth), maximum)
  }

  // Height the side panel would like, so short lists still show the whole image or text.
  static func detailPreferredHeight(imageSize: NSSize?, text: String, limit: CGFloat) -> CGFloat {
    let padding = detailPadding * 2
    if let imageSize {
      return min(limit, imageSize.height.rounded() + padding + detailActionBarHeight)
    }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { total, line in
      total + max(1, Int((Double(line.count) / Double(detailCharactersPerLine)).rounded(.up)))
    }
    return min(limit, CGFloat(lines) * detailLineHeight + padding)
  }

  @MainActor
  func toggleDetail(for item: HistoryItemDecorator) {
    if detailItem === item {
      closeDetail()
      return
    }
    let previous = detailItem
    detailItem = item
    previous?.releaseExpandedContent()
    item.ensureExpandedContent()

    let imageSize = item.imageSize
    let limit = Self.maximumHeight(for: Defaults[.windowSize].height)
    detailPreferredHeight = Self.detailPreferredHeight(imageSize: imageSize, text: item.expandedText, limit: limit)
    let panel = AppState.shared.appDelegate?.panel
    let screenWidth = (panel?.screen ?? NSScreen.main)?.visibleFrame.width ?? limit * 2
    let width = Self.detailWidth(
      imageSize: imageSize, panelHeight: preferredHeight(for: height), screenWidth: screenWidth
    )
    if let layout = panel?.showDetail(width: width) {
      detailWidth = layout.detailWidth
      detailSide = layout.side
    } else {
      detailWidth = width
    }
    needsResize = true
  }

  @MainActor
  func closeDetail() {
    guard let item = detailItem else { return }
    detailItem = nil
    detailWidth = 0
    detailPreferredHeight = 0
    item.releaseExpandedContent()
    AppState.shared.appDelegate?.panel.hideDetail()
    needsResize = true
  }

  func resize(height: CGFloat) {
    self.height = height + headerHeight + extraTopHeight + extraBottomHeight + footerHeight
    AppState.shared.appDelegate?.panel.verticallyResize(to: preferredHeight(for: self.height))
    needsResize = false
  }

  private func handleFirstKeyDown() {
    if isClosed() {
      open(height: height)
      state = .opening
      KeyboardShortcuts.disable(.popup)  // Handle events via eventsMonitor. Re-enable on popup close
      return
    }

    // MultiRam was not opened via shortcut. We assume toggle mode and close it
    close()
  }

  // The fallback shortcut only toggles the popup; cycling through items stays on the main shortcut.
  private func handleFallbackKeyDown() {
    // A fallback equal to the main shortcut is handled by the main handler alone.
    guard KeyboardShortcuts.getShortcut(for: .popupFallback) != KeyboardShortcuts.getShortcut(for: .popup) else {
      return
    }
    if isClosed() {
      open(height: height)
      state = .toggle
    } else {
      close()
    }
  }

  private func handleEvent(_ event: NSEvent) -> NSEvent? {
    switch event.type {
    case .keyDown:
      return handleKeyDown(event)
    case .flagsChanged:
      return handleFlagsChanged(event)
    default:
      return event
    }
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if isHotKeyCode(Int(event.keyCode)) {
      if let item = History.shared.pressedShortcutItem {
        AppState.shared.navigator.select(item: item)
        Task { @MainActor in
          AppState.shared.history.select(item)
        }
        return nil
      }

      if state == .opening {
        state = .cycle
        // Next 'if' will highlight next item and then return nil
      }

      if state == .cycle {
        AppState.shared.navigator.highlightNext(allowCycle: true)
        return nil
      }

      if state == .toggle && isHotKeyModifiers(event.modifierFlags) {
        close()
        return nil
      }
    }

    return event
  }

  private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
    // If we are in cycle mode, releasing modifiers triggers a selection
    if state == .cycle && allModifiersReleased(event) {
      DispatchQueue.main.async {
        AppState.shared.select()
      }
      return nil
    }

    // Otherwise if in opening mode, enter toggle mode
    if state == .opening && allModifiersReleased(event) {
      state = .toggle
      return event
    }

    return event
  }

  private func isHotKeyCode(_ keyCode: Int) -> Bool {
    guard let shortcut = KeyboardShortcuts.Name.popup.shortcut else {
      return false
    }

    return shortcut.key?.rawValue == keyCode
  }

  private func isHotKeyModifiers(_ modifiers: NSEvent.ModifierFlags) -> Bool {
    guard let shortcut = KeyboardShortcuts.Name.popup.shortcut else {
      return false
    }

    return modifiers.intersection(.deviceIndependentFlagsMask) ==
      shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
  }

  private func allModifiersReleased(_ event: NSEvent) -> Bool {
    return event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask)
  }
}
