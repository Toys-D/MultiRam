import Defaults
import KeyboardShortcuts
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  var panel: FloatingPanel<ContentView>!

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = Defaults[.menuIcon].image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?
  private var retentionTimer: Timer?
  private var secureInputBubble: SecureInputBubble?
  private var secureInputBubbleSchedule = SecureInputBubbleSchedule()

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    // After a relaunch, let the previous instance release the hotkeys and the clipboard first.
    AppRelauncher.finishRelaunch()
    Accessibility.noteLaunch()

    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    let unitTesting = CommandLine.arguments.contains("unit-testing") ||
      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    if !unitTesting {
      Clipboard.shared.onNewCopy { History.shared.add($0) }
      Clipboard.shared.start()
      Task {
        for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
          Clipboard.shared.restart()
        }
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    Task {
      for await _ in Defaults.updates(.menuIcon, initial: false) {
        updateStatusItemImage()
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }

    if !unitTesting {
      History.shared.onClear = { OpenWithController.shared.removeAllCopies() }
      observeSecureInput()
      updateSecureInputMonitoring()
      NotificationCenter.default.addObserver(
        forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
        object: nil,
        queue: .main
      ) { [weak self] notification in
        let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name
        if name == .popup || name == .popupFallback {
          MainActor.assumeIsolated {
            self?.updateSecureInputMonitoring()
          }
        }
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    migrateUserDefaults()
    disableUnusedGlobalHotkeys()

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "local.multiram.MultiRam",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }

    OpenWithController.shared.purgeOldCopies()
    startRemovingExpiredItems()
  }

  // Expired items also go away while MultiRam keeps running for days.
  private func startRemovingExpiredItems() {
    guard !CommandLine.arguments.contains("unit-testing"),
          ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    let timer = Timer(timeInterval: 60 * 60, repeats: true) { _ in
      MainActor.assumeIsolated {
        AppState.shared.history.removeExpired()
      }
    }
    timer.tolerance = 5 * 60
    RunLoop.main.add(timer, forMode: .common)
    retentionTimer = timer
    MainActor.assumeIsolated {
      SoftwareUpdater.shared.start()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    // A relaunch is not a quit: the new instance continues the session and clears it on the real quit.
    if Defaults[.clearOnQuit] && !AppRelauncher.isTerminatingForRelaunch {
      AppState.shared.history.clear()
    }
    // A detached task would not finish before the process exits.
    OpenWithController.shared.purgeOldCopiesNow()
  }

  private func migrateUserDefaults() {
    if Defaults[.migrations]["2024-07-01-version-2"] != true {
      // Start 2.x from scratch.
      Defaults.reset(.migrations)

      // Inverse hide* configuration keys.
      Defaults[.showFooter] = !UserDefaults.standard.bool(forKey: "hideFooter")
      Defaults[.showSearch] = !UserDefaults.standard.bool(forKey: "hideSearch")
      Defaults[.showTitle] = !UserDefaults.standard.bool(forKey: "hideTitle")
      UserDefaults.standard.removeObject(forKey: "hideFooter")
      UserDefaults.standard.removeObject(forKey: "hideSearch")
      UserDefaults.standard.removeObject(forKey: "hideTitle")

      Defaults[.migrations]["2024-07-01-version-2"] = true
    }

    // The following defaults are not used in MultiRam 2.x
    // and should be removed in 3.x.
    // - LaunchAtLogin__hasMigrated
    // - avoidTakingFocus
    // - saratovSeparator
    // - maxMenuItemLength
    // - maxMenuItems
  }

  @objc @MainActor
  private func performStatusItemClick() {
    if let event = NSApp.currentEvent {
      let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifierFlags.contains(.option) {
        Defaults[.ignoreEvents].toggle()

        if modifierFlags.contains(.shift) {
          Defaults[.ignoreOnlyNextEvent] = Defaults[.ignoreEvents]
        }

        return
      }
    }

    panel.close()
    statusItem.menu = makeStatusMenu()
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  @MainActor
  private func makeStatusMenu() -> NSMenu {
    let menu = NSMenu()
    if let lines = secureInputHintLines {
      for line in lines {
        let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
      }
      menu.addItem(.separator())
    }
    let commands: [(String, Selector, String)] = [
      ("show_history", #selector(showHistory), ""),
      ("preferences", #selector(showPreferences), ","),
      ("about", #selector(showAbout), ""),
      ("quit", #selector(quit), "q")
    ]

    for (title, action, key) in commands {
      if title == "preferences" || title == "quit" {
        menu.addItem(.separator())
      }
      let item = NSMenuItem(title: NSLocalizedString(title, comment: ""), action: action, keyEquivalent: key)
      item.target = self
      menu.addItem(item)
    }
    return menu
  }

  @objc private func showHistory() {
    // Wait until the status menu closes before making the panel key.
    DispatchQueue.main.async {
      self.panel.open(height: AppState.shared.popup.height, at: .statusItem)
    }
  }

  @objc private func showPreferences() {
    DispatchQueue.main.async {
      AppState.shared.openPreferences()
    }
  }

  @objc private func showAbout() {
    DispatchQueue.main.async {
      AppState.shared.openAbout()
    }
  }

  @objc private func quit() {
    AppState.shared.quit()
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

  // MARK: Secure Event Input

  // True when the main shortcut is one macOS withholds during Secure Event Input.
  private var popupShortcutIsBlockable: Bool {
    HotkeySecurity.isBlockedBySecureInput(KeyboardShortcuts.getShortcut(for: .popup))
  }

  @MainActor
  private var secureInputHintLines: [String]? {
    guard SecureInputMonitor.shared.isEnabled, let popup = KeyboardShortcuts.getShortcut(for: .popup),
          HotkeySecurity.isBlockedBySecureInput(popup) else {
      return nil
    }
    return SecureInputHint.lines(
      blocked: popup,
      holder: SecureInputMonitor.shared.holderName,
      fallback: KeyboardShortcuts.getShortcut(for: .popupFallback)
    )
  }

  // Polls only while the main shortcut could be withheld; Command or Control shortcuts always work.
  @MainActor
  private func updateSecureInputMonitoring() {
    if popupShortcutIsBlockable {
      SecureInputMonitor.shared.start()
    } else {
      SecureInputMonitor.shared.stop()
    }
    updateStatusItemImage()
  }

  @MainActor
  private func observeSecureInput() {
    _ = withObservationTracking {
      (SecureInputMonitor.shared.isEnabled, SecureInputMonitor.shared.holderName)
    } onChange: {
      Task { @MainActor [weak self] in
        self?.updateStatusItemImage()
        self?.showSecureInputBubbleIfNeeded()
        self?.observeSecureInput()
      }
    }
  }

  // Pops a note under the icon when the main shortcut starts being withheld, because the lock
  // on the icon alone is easy to miss. Clicking the note opens the history.
  @MainActor
  private func showSecureInputBubbleIfNeeded() {
    let lines = secureInputHintLines
    let show = secureInputBubbleSchedule.shouldShow(
      blocked: lines != nil, holder: SecureInputMonitor.shared.holderName, now: Date()
    )
    guard let lines else {
      secureInputBubble?.hide()
      return
    }
    guard show else { return }
    let bubble = secureInputBubble ?? SecureInputBubble()
    bubble.onClick = { [weak self] in self?.showHistory() }
    secureInputBubble = bubble
    bubble.show(lines: lines, below: statusItem.isVisible ? statusItem.button : nil)
  }

  // Adds a lock to the menu bar icon and explains it in the tooltip while the shortcut is withheld.
  @MainActor
  private func updateStatusItemImage() {
    let icon = Defaults[.menuIcon].image
    if let lines = secureInputHintLines {
      statusItem.button?.image = SecureInputHint.badgedImage(icon)
      statusItem.button?.toolTip = lines.joined(separator: "\n")
    } else {
      statusItem.button?.image = icon
      statusItem.button?.toolTip = nil
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}
