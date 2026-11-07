import AppKit
import KeyboardShortcuts
import SwiftUI

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

// Decides when the bubble appears: when Secure Input starts withholding the main shortcut,
// and at most once per app per interval, since browsers turn it on at every password field.
struct SecureInputBubbleSchedule {
  var interval: TimeInterval
  private var lastShown: [String: Date] = [:]
  private var wasBlocked = false

  init(interval: TimeInterval = 30 * 60) {
    self.interval = interval
  }

  mutating func shouldShow(blocked: Bool, holder: String?, now: Date) -> Bool {
    defer { wasBlocked = blocked }
    guard blocked, !wasBlocked else { return false }
    let key = holder ?? ""
    if let last = lastShown[key], now.timeIntervalSince(last) < interval {
      return false
    }
    lastShown[key] = now
    return true
  }
}

// A small note under the menu bar icon that explains why the main shortcut does nothing right now.
// The panel never becomes key, so the password field keeps its focus.
@MainActor
final class SecureInputBubble {
  var onClick: () -> Void = {}

  private var panel: NSPanel?
  private var hideTask: Task<Void, Never>?

  func show(lines: [String], below button: NSStatusBarButton?, duration: TimeInterval = 8) {
    hide()

    let content = NSHostingView(rootView: SecureInputBubbleView(lines: lines) { [weak self] in
      self?.hide()
      self?.onClick()
    })
    let size = content.fittingSize
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = content
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.isReleasedWhenClosed = false
    panel.setFrameOrigin(Self.origin(for: size, below: button))
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
    self.panel = panel

    hideTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(duration))
      guard !Task.isCancelled else { return }
      self?.fadeOut()
    }
  }

  func hide() {
    hideTask?.cancel()
    hideTask = nil
    panel?.orderOut(nil)
    panel = nil
  }

  private func fadeOut() {
    guard let panel else { return }
    NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) { [weak self] in
      MainActor.assumeIsolated {
        if self?.panel === panel { self?.hide() }
      }
    }
  }

  // Under the icon when it is on screen, otherwise in the top right corner of the main screen.
  private static func origin(for size: NSSize, below button: NSStatusBarButton?) -> NSPoint {
    let gap: CGFloat = 6
    if let window = button?.window, window.isVisible, let screen = window.screen,
       screen.frame.intersects(window.frame) {
      let visible = screen.visibleFrame
      let x = min(max(window.frame.midX - size.width / 2, visible.minX + gap), visible.maxX - size.width - gap)
      return NSPoint(x: x, y: window.frame.minY - size.height - gap)
    }
    let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    return NSPoint(x: visible.maxX - size.width - gap, y: visible.maxY - size.height - gap)
  }
}

private struct SecureInputBubbleView: View {
  let lines: [String]
  let action: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "lock.fill")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.orange)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 3) {
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
          Text(line)
            .font(.system(size: 12.5, weight: index == 0 ? .semibold : .regular))
            .foregroundStyle(index == 0 ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(width: 300, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
    .contentShape(RoundedRectangle(cornerRadius: 12))
    .onTapGesture(perform: action)
    .accessibilityIdentifier("secure-input-bubble")
  }
}
