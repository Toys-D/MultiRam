import AppKit
import os

// What automatic pasting can do right now.
enum PasteAccess: Equatable {
  case granted
  // Accessibility is on, but this process still sees the denial it got before the grant.
  case needsRelaunch
  case needsPermission
}

struct Accessibility {
  static var canPaste: Bool { CGPreflightPostEventAccess() }
  // Asks tccd on every call. The event-posting preflight above does not: WindowServer answers it
  // from a cache that lives as long as the process, so a later grant only shows up after a relaunch.
  static var isTrusted: Bool { AXIsProcessTrusted() }

  // Set once this process has seen Accessibility off, at launch or at a check. WindowServer may have
  // cached the event-posting denial then. A process that never saw it off holds a real denial.
  private(set) static var sawAccessibilityOff = false

  private static let logger = Logger(subsystem: "local.multiram.MultiRam", category: "PasteAccess")

  // macOS 27 renamed the Accessibility list in Privacy & Security to Device Control and Data Access.
  static func paneNameKey(majorVersion: Int) -> String {
    majorVersion >= 27 ? "accessibility_pane_macos27" : "accessibility_pane"
  }

  static func localized(_ key: String) -> String {
    let pane = paneNameKey(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    return NSLocalizedString(key, comment: "")
      .replacingOccurrences(of: "{accessibility}", with: NSLocalizedString(pane, comment: ""))
      .replacingOccurrences(of: "{pane}", with: NSLocalizedString("system_settings_pane", comment: ""))
      .replacingOccurrences(of: "{settings}", with: NSLocalizedString("system_settings_name", comment: ""))
  }

  static func noteLaunch() {
    if !isTrusted {
      sawAccessibilityOff = true
    }
  }

  // Event posting is granted through the Accessibility list. A trusted process that cannot post events
  // holds a stale answer only if it saw Accessibility off; otherwise a relaunch would not change anything.
  static func access(canPostEvents: Bool, isTrusted: Bool, sawAccessibilityOff: Bool) -> PasteAccess {
    if canPostEvents {
      return .granted
    }
    return isTrusted && sawAccessibilityOff ? .needsRelaunch : .needsPermission
  }

  @MainActor
  @discardableResult
  static func check() -> Bool {
    let trusted = isTrusted
    if !trusted {
      sawAccessibilityOff = true
    }
    switch access(canPostEvents: canPaste, isTrusted: trusted, sawAccessibilityOff: sawAccessibilityOff) {
    case .granted:
      return true
    case .needsRelaunch:
      logger.notice("Accessibility is on, but event posting is still denied for this process")
      askToRelaunch()
    case .needsPermission:
      logger.notice("Event posting is not allowed")
      askForPermission()
      // Started even if access was turned on while the alert was open: the first tick relaunches then.
      if !trusted {
        AccessibilityGrantWatcher.shared.start()
      }
    }
    // Never paste into the permission dialog or System Settings. The selected
    // content stays on the clipboard; the user can retry in the target app.
    return false
  }

  @MainActor
  private static func askForPermission() {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("accessibility_alert_message", comment: "")
    alert.informativeText = localized("accessibility_alert_comment")
    alert.addButton(withTitle: NSLocalizedString("accessibility_alert_open", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("accessibility_alert_deny", comment: ""))
    alert.window.identifier = NSUserInterfaceItemIdentifier("paste-permission-required")
    NSApp.activate()
    if alert.runModal() == .alertFirstButtonReturn {
      // Register an event-posting access request before opening the settings pane.
      CGRequestPostEventAccess()
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
      }
    }
  }

  @MainActor
  private static func askToRelaunch() {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("accessibility_relaunch_message", comment: "")
    alert.informativeText = localized("accessibility_relaunch_comment")
    alert.addButton(withTitle: NSLocalizedString("accessibility_relaunch_button", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("accessibility_alert_deny", comment: ""))
    alert.window.identifier = NSUserInterfaceItemIdentifier("paste-relaunch-required")
    NSApp.activate()
    if alert.runModal() == .alertFirstButtonReturn {
      AppRelauncher.relaunch()
    }
  }
}

// Relaunches MultiRam as soon as Accessibility is turned on, so the user does not have to quit
// and reopen it for the new permission to take effect.
@MainActor
final class AccessibilityGrantWatcher {
  static let shared = AccessibilityGrantWatcher(
    interval: 1,
    timeout: 60 * 60,
    isTrusted: { Accessibility.isTrusted },
    canPostEvents: { Accessibility.canPaste },
    relaunch: { AppRelauncher.relaunch() },
    now: { Date() }
  )

  private let interval: TimeInterval
  private let timeout: TimeInterval
  private let isTrusted: () -> Bool
  private let canPostEvents: () -> Bool
  private let relaunch: () -> Void
  private let now: () -> Date
  private var timer: Timer?
  private var deadline: Date?

  var isWatching: Bool { timer != nil }

  init(
    interval: TimeInterval,
    timeout: TimeInterval,
    isTrusted: @escaping () -> Bool,
    canPostEvents: @escaping () -> Bool,
    relaunch: @escaping () -> Void,
    now: @escaping () -> Date
  ) {
    self.interval = interval
    self.timeout = timeout
    self.isTrusted = isTrusted
    self.canPostEvents = canPostEvents
    self.relaunch = relaunch
    self.now = now
  }

  // Start only after seeing Accessibility off: a grant that already fails is not fixed by a relaunch.
  func start() {
    deadline = now().addingTimeInterval(timeout)
    guard timer == nil else { return }
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    timer.tolerance = interval / 4
    // Common modes keep checking while an alert or a menu runs the loop.
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func tick() {
    guard isWatching else { return }
    if isTrusted() {
      stop()
      if !canPostEvents() {
        relaunch()
      }
    } else if let deadline, now() >= deadline {
      stop()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    deadline = nil
  }
}
