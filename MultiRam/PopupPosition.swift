import AppKit.NSEvent
import Defaults
import Foundation

enum PopupPosition: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case cursor
  case statusItem
  case window
  case center
  case lastPosition

  var id: Self { self }

  func screen(statusBarButton: NSStatusBarButton?) -> NSScreen? {
    switch self {
    case .cursor:
      return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.forPopup
    case .statusItem:
      return statusBarButton?.window?.screen ?? NSScreen.main
    case .window:
      if let frame = NSWorkspace.shared.frontmostApplication?.windowFrame,
         let screen = NSScreen.screens.max(by: {
           $0.frame.intersection(frame).area < $1.frame.intersection(frame).area
         }) {
        return screen
      }
      return NSScreen.forPopup
    default:
      return NSScreen.forPopup
    }
  }

  static func frameAtCursor(size: NSSize, cursor: NSPoint, visibleFrame: NSRect) -> NSRect {
    var frame = NSRect(x: cursor.x, y: cursor.y - size.height, width: size.width, height: size.height)
    if frame.minY < visibleFrame.minY {
      frame.origin.y = cursor.y
    }
    return frame.constrained(to: visibleFrame)
  }

  var description: String {
    switch self {
    case .cursor:
      return NSLocalizedString("PopupAtCursor", tableName: "AppearanceSettings", comment: "")
    case .statusItem:
      return NSLocalizedString("PopupAtMenuBarIcon", tableName: "AppearanceSettings", comment: "")
    case .window:
      return NSLocalizedString("PopupAtWindowCenter", tableName: "AppearanceSettings", comment: "")
    case .center:
      return NSLocalizedString("PopupAtScreenCenter", tableName: "AppearanceSettings", comment: "")
    case .lastPosition:
      return NSLocalizedString("PopupAtLastPosition", tableName: "AppearanceSettings", comment: "")
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func origin(size: NSSize, statusBarButton: NSStatusBarButton?) -> NSPoint {
    switch self {
    case .center:
      if let frame = NSScreen.forPopup?.visibleFrame {
        return NSRect.centered(ofSize: size, in: frame).origin
      }
    case .window:
      if let frame = NSWorkspace.shared.frontmostApplication?.windowFrame {
        return NSRect.centered(ofSize: size, in: frame).origin
      }
    case .statusItem:
      if let statusBarButton, let screen = statusBarButton.window?.screen ?? NSScreen.main {
        let rectInWindow = statusBarButton.convert(statusBarButton.bounds, to: nil)
        if let screenRect = statusBarButton.window?.convertToScreen(rectInWindow) {
          var topLeftPoint = NSPoint(x: screenRect.minX, y: screenRect.minY - size.height)
          // Ensure that window doesn't spill over to the right screen.
          if (topLeftPoint.x + size.width) > screen.visibleFrame.maxX {
            topLeftPoint.x = screen.visibleFrame.maxX - size.width
          }

          return topLeftPoint
        }
      }
    case .lastPosition:
      if let frame = NSScreen.forPopup?.visibleFrame {
        let relativePos = Defaults[.windowPosition]
        let anchorX = frame.minX + frame.width * relativePos.x
        let anchorY = frame.minY + frame.height * relativePos.y
        // Anchor is top middle of frame
        return NSPoint(x: anchorX - size.width / 2, y: anchorY - size.height)
      }
    default:
      break
    }

    let cursor = NSEvent.mouseLocation
    if let visibleFrame = screen(statusBarButton: statusBarButton)?.visibleFrame {
      return Self.frameAtCursor(size: size, cursor: cursor, visibleFrame: visibleFrame).origin
    }
    return NSPoint(x: cursor.x, y: cursor.y - size.height)
  }
}

private extension NSRect {
  var area: CGFloat { isNull ? 0 : width * height }
}
