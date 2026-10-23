import AppKit
import KeyboardShortcuts

// Text and menu bar icon that explain why the main shortcut does not open MultiRam right now.
enum SecureInputHint {
  @MainActor
  static func lines(
    blocked: KeyboardShortcuts.Shortcut,
    holder: String?,
    fallback: KeyboardShortcuts.Shortcut?
  ) -> [String] {
    let application = holder ?? NSLocalizedString("secure_input_unknown_app", comment: "")
    let reason = String(
      format: NSLocalizedString("secure_input_blocked", comment: ""),
      blocked.description, application
    )
    // Suggest the fallback only when macOS would deliver it during Secure Event Input.
    if let fallback, !HotkeySecurity.isBlockedBySecureInput(fallback) {
      return [reason, String(format: NSLocalizedString("secure_input_use_fallback", comment: ""), fallback.description)]
    }
    return [reason, NSLocalizedString("secure_input_use_icon", comment: "")]
  }

  @MainActor
  static func message(
    blocked: KeyboardShortcuts.Shortcut,
    holder: String?,
    fallback: KeyboardShortcuts.Shortcut?
  ) -> String {
    lines(blocked: blocked, holder: holder, fallback: fallback).joined(separator: "\n")
  }

  // The menu bar icon with a small lock in its lower right corner.
  static func badgedImage(_ image: NSImage) -> NSImage {
    let size = image.size
    let configuration = NSImage.SymbolConfiguration(pointSize: max(6, size.height * 0.48), weight: .heavy)
    let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)

    let badged = NSImage(size: size, flipped: false) { rect in
      image.draw(in: rect)
      guard let lock, let context = NSGraphicsContext.current else { return true }
      let lockRect = NSRect(
        x: rect.maxX - lock.size.width, y: rect.minY,
        width: lock.size.width, height: lock.size.height
      )
      // Clear a thin gap around the lock so it stays readable on top of the icon.
      context.compositingOperation = .destinationOut
      NSColor.black.setFill()
      NSBezierPath(roundedRect: lockRect.insetBy(dx: -1.5, dy: -1.5), xRadius: 2, yRadius: 2).fill()
      context.compositingOperation = .sourceOver
      lock.draw(in: lockRect)
      return true
    }
    badged.isTemplate = true
    return badged
  }
}
