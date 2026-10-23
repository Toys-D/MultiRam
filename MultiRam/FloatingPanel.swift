import Defaults
import SwiftUI

private final class PanelHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// An NSPanel subclass that implements floating panel traits.
// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
  var isPresented: Bool = false
  var statusBarButton: NSStatusBarButton?
  let onClose: () -> Void
  private var openingScreen: NSScreen?
  private var cursorAnchor: NSPoint?
  private var userResizeInProgress = false
  // Width and side of the detail panel currently added to the list frame.
  private(set) var detailWidth: CGFloat = 0
  private(set) var detailSide: DetailPanelSide = .trailing

  override var isMovable: Bool {
    get { Defaults[.popupPosition] != .statusItem }
    set {}
  }

  init(
    contentRect: NSRect,
    identifier: String = "",
    statusBarButton: NSStatusBarButton? = nil,
    onClose: @escaping () -> Void,
    view: () -> Content
  ) {
    self.onClose = onClose
    var contentRect = contentRect
    contentRect.size.height = Popup.maximumHeight(for: contentRect.height)

    super.init(
        contentRect: contentRect,
        styleMask: [.nonactivatingPanel, .resizable, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )

    self.statusBarButton = statusBarButton
    self.identifier = NSUserInterfaceItemIdentifier(identifier)

    Defaults[.windowSize] = contentRect.size
    delegate = self

    animationBehavior = .none
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = false
    hidesOnDeactivate = false
    backgroundColor = .clear
    titlebarSeparatorStyle = .none

    // Hide all traffic light buttons
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    contentView = PanelHostingView(
      rootView: view()
        // The safe area is ignored because the title bar still interferes with the geometry
        .ignoresSafeArea()
    )
    contentView?.layer?.cornerRadius = Popup.cornerRadius + Popup.horizontalPadding
  }

  func toggle(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    if isPresented {
      close()
    } else {
      open(height: height, at: popupPosition)
    }
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    let size = Defaults[.windowSize]
    detailWidth = 0
    openingScreen = popupPosition.screen(statusBarButton: statusBarButton)
    cursorAnchor = popupPosition == .cursor ? NSEvent.mouseLocation : nil
    let newSize = NSSize(
      width: max(size.width, Popup.minimumWindowWidth),
      height: AppState.shared.popup.preferredHeight(for: height)
    )
    let newFrame = NSRect(
      origin: popupPosition.origin(size: newSize, statusBarButton: statusBarButton),
      size: newSize
    )
    setFrame(constrainedPopupFrame(newFrame, on: openingScreen), display: false)
    orderFrontRegardless()
    makeKey()
    isPresented = true

    if popupPosition == .statusItem {
      DispatchQueue.main.async {
        self.statusBarButton?.isHighlighted = true
      }
    }
  }

  func verticallyResize(to newHeight: CGFloat) {
    guard !inLiveResize else { return }
    var newSize = frame.size
    newSize.height = newHeight
    var newOrigin = frame.origin
    newOrigin.y += (frame.height - newSize.height)

    let newFrame = constrainedPopupFrame(NSRect(origin: newOrigin, size: newSize))
    guard newFrame != frame else { return }
    NSAnimationContext.runAnimationGroup { (context) in
      context.duration = 0.2
      animator().setFrame(newFrame, display: true)
    }
  }

  // Widens the window by the detail panel on the side that fits; the result may be narrower than asked.
  @discardableResult
  func showDetail(width: CGFloat) -> DetailPanelLayout {
    let listFrame = DetailPanelLayout.collapsed(frame: frame, side: detailSide, detailWidth: detailWidth)
    guard let visibleFrame = (screen ?? openingScreen)?.visibleFrame else {
      return DetailPanelLayout(frame: frame, side: detailSide, detailWidth: width)
    }
    let layout = DetailPanelLayout.expanded(listFrame: listFrame, detailWidth: width, visibleFrame: visibleFrame)
    detailWidth = layout.detailWidth
    detailSide = layout.side
    setFrame(layout.frame, display: true)
    return layout
  }

  func hideDetail() {
    guard detailWidth > 0 else { return }
    let listFrame = DetailPanelLayout.collapsed(frame: frame, side: detailSide, detailWidth: detailWidth)
    detailWidth = 0
    setFrame(listFrame, display: true)
  }

  func constrainedPopupFrame(_ proposedFrame: NSRect, on targetScreen: NSScreen? = nil) -> NSRect {
    guard let visibleFrame = (targetScreen ?? screen ?? openingScreen)?.visibleFrame else {
      return proposedFrame
    }
    var result = proposedFrame
    if let cursorAnchor, !inLiveResize {
      // Keep the opening cursor as the anchor while image thumbnails load.
      let cursorFrame = PopupPosition.frameAtCursor(
        size: result.size, cursor: cursorAnchor, visibleFrame: visibleFrame
      )
      result.origin.y = cursorFrame.minY
    }
    return result.constrained(to: visibleFrame)
  }

  func drag(with event: NSEvent) {
    guard isMovable else { return }
    cursorAnchor = nil
    performDrag(with: event)
    saveWindowPosition()
  }

  func saveWindowPosition() {
    if let screenFrame = screen?.visibleFrame {
      // The anchor describes the list only, so reopening without the panel keeps it in place.
      let listFrame = DetailPanelLayout.collapsed(frame: frame, side: detailSide, detailWidth: detailWidth)
      let anchorX = listFrame.midX - screenFrame.minX
      let anchorY = listFrame.maxY - screenFrame.minY
      Defaults[.windowPosition] = NSPoint(x: anchorX / screenFrame.width, y: anchorY / screenFrame.height)
    }
  }

  func saveWindowFrame(frame: NSRect) {
    // Only the list is remembered; the detail panel is sized from its content.
    Defaults[.windowSize] = NSSize(width: frame.width - detailWidth, height: frame.height)
    saveWindowPosition()
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    if inLiveResize {
      userResizeInProgress = true
      cursorAnchor = nil
    }

    var finalFrameSize = frameSize
    if inLiveResize {
      finalFrameSize.height = max(frameSize.height, Popup.minimumWindowHeight)
    }
    finalFrameSize.width = max(finalFrameSize.width, Popup.minimumWindowWidth + detailWidth)

    return finalFrameSize
  }

  func windowWillMove(_ notification: Notification) {
    if NSApp.currentEvent?.type == .leftMouseDragged {
      cursorAnchor = nil
    }
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    // AppKit also sends this notification after automatic hosting-view layout.
    // Only a resize started by windowWillResize should update the user's limit.
    guard userResizeInProgress else { return }
    userResizeInProgress = false
    saveWindowFrame(frame: frame)
  }

  // Close automatically when out of focus, e.g. outside click.
  override func resignKey() {
    super.resignKey()
    // Don't hide if confirmation is shown.
    if NSApp.alertWindow == nil {
      close()
    }
  }

  override func close() {
    super.close()
    isPresented = false
    detailWidth = 0
    cursorAnchor = nil
    statusBarButton?.isHighlighted = false
    onClose()
  }

  // Allow text inputs inside the panel can receive focus
  override var canBecomeKey: Bool {
    return true
  }
}
