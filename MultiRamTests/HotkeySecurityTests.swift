import AppKit
import KeyboardShortcuts
import XCTest
@testable import MultiRam

@MainActor
final class HotkeySecurityTests: XCTestCase {
  typealias Shortcut = KeyboardShortcuts.Shortcut

  func testOptionCharacterShortcutsAreWithheldBySecureInput() {
    XCTAssertTrue(HotkeySecurity.isBlockedBySecureInput(Shortcut(.v, modifiers: [.option])))
    XCTAssertTrue(HotkeySecurity.isBlockedBySecureInput(Shortcut(.v, modifiers: [.option, .shift])))
    XCTAssertTrue(HotkeySecurity.isBlockedBySecureInput(Shortcut(.one, modifiers: [.option])))
    XCTAssertTrue(HotkeySecurity.isBlockedBySecureInput(Shortcut(.v)))
  }

  func testCommandOrControlShortcutsAreDelivered() {
    XCTAssertFalse(HotkeySecurity.isBlockedBySecureInput(Shortcut(.v, modifiers: [.control, .option])))
    XCTAssertFalse(HotkeySecurity.isBlockedBySecureInput(Shortcut(.v, modifiers: [.command, .shift])))
    XCTAssertFalse(HotkeySecurity.isBlockedBySecureInput(Shortcut(.v, modifiers: [.control])))
  }

  func testNonCharacterKeysAreDelivered() {
    XCTAssertFalse(HotkeySecurity.isBlockedBySecureInput(Shortcut(.space, modifiers: [.option])))
    XCTAssertFalse(HotkeySecurity.isBlockedBySecureInput(Shortcut(.f19, modifiers: [.option])))
    XCTAssertFalse(HotkeySecurity.isBlockedBySecureInput(Shortcut(.upArrow, modifiers: [.option])))
    XCTAssertFalse(HotkeySecurity.isBlockedBySecureInput(Shortcut(.keypad1, modifiers: [.option])))
  }

  func testMissingShortcutIsNotBlocked() {
    XCTAssertFalse(HotkeySecurity.isBlockedBySecureInput(nil))
  }

  func testDefaultFallbackWorksInPasswordFields() {
    let fallback = KeyboardShortcuts.Name.popupFallback.defaultShortcut
    XCTAssertEqual(fallback, Shortcut(.v, modifiers: [.control, .option]))
    XCTAssertFalse(HotkeySecurity.isBlockedBySecureInput(fallback))
    XCTAssertTrue(HotkeySecurity.isBlockedBySecureInput(KeyboardShortcuts.Name.popup.defaultShortcut))
  }

  func testHintNamesTheBlockedShortcutTheHolderAndTheFallback() {
    let blocked = Shortcut(.v, modifiers: [.option])
    let fallback = Shortcut(.v, modifiers: [.control, .option])
    let message = SecureInputHint.message(blocked: blocked, holder: "Google Chrome", fallback: fallback)
    XCTAssertTrue(message.contains(blocked.description), message)
    XCTAssertTrue(message.contains("Google Chrome"), message)
    XCTAssertTrue(message.contains(fallback.description), message)
  }

  func testHintWithoutFallbackPointsToTheMenuBarIcon() {
    let blocked = Shortcut(.v, modifiers: [.option])
    let fallback = Shortcut(.v, modifiers: [.control, .option])
    let withFallback = SecureInputHint.message(blocked: blocked, holder: nil, fallback: fallback)
    let withoutFallback = SecureInputHint.message(blocked: blocked, holder: nil, fallback: nil)
    XCTAssertNotEqual(withFallback, withoutFallback)
    XCTAssertFalse(withoutFallback.contains(fallback.description), withoutFallback)
    XCTAssertTrue(withoutFallback.contains(blocked.description), withoutFallback)
  }

  func testUnusableFallbackIsNotSuggested() {
    let blocked = Shortcut(.v, modifiers: [.option])
    let alsoBlocked = Shortcut(.c, modifiers: [.option])
    XCTAssertEqual(
      SecureInputHint.message(blocked: blocked, holder: nil, fallback: alsoBlocked),
      SecureInputHint.message(blocked: blocked, holder: nil, fallback: nil)
    )
  }

  func testBadgedIconKeepsSizeAndStaysATemplate() throws {
    let base = try XCTUnwrap(NSImage(named: .multiramStatusBar))
    let badged = SecureInputHint.badgedImage(base)
    XCTAssertEqual(badged.size, base.size)
    XCTAssertTrue(badged.isTemplate)
    XCTAssertNotEqual(badged.tiffRepresentation, base.tiffRepresentation)
  }
}

// Equal main and fallback shortcuts share one Carbon hot key: both handlers would run on one press.
final class ShortcutConflictTests: XCTestCase {
  typealias Shortcut = KeyboardShortcuts.Shortcut

  private let savedPopup = KeyboardShortcuts.getShortcut(for: .popup)
  private let savedFallback = KeyboardShortcuts.getShortcut(for: .popupFallback)

  override func tearDown() {
    KeyboardShortcuts.setShortcut(savedPopup, for: .popup)
    KeyboardShortcuts.setShortcut(savedFallback, for: .popupFallback)
    KeyboardShortcuts.enable(.popup, .popupFallback)
    super.tearDown()
  }

  func testFallbackEqualToTheMainShortcutIsCleared() {
    let shared = Shortcut(.v, modifiers: [.control, .option])
    KeyboardShortcuts.setShortcut(shared, for: .popup)
    KeyboardShortcuts.setShortcut(shared, for: .popupFallback)

    XCTAssertTrue(Popup.resolveShortcutConflict())
    XCTAssertEqual(KeyboardShortcuts.getShortcut(for: .popup), shared)
    XCTAssertNil(KeyboardShortcuts.getShortcut(for: .popupFallback))
  }

  func testDifferentShortcutsAreKept() {
    KeyboardShortcuts.setShortcut(Shortcut(.v, modifiers: [.option]), for: .popup)
    KeyboardShortcuts.setShortcut(Shortcut(.v, modifiers: [.control, .option]), for: .popupFallback)

    XCTAssertFalse(Popup.resolveShortcutConflict())
    XCTAssertEqual(KeyboardShortcuts.getShortcut(for: .popupFallback), Shortcut(.v, modifiers: [.control, .option]))
  }
}

@MainActor
final class SecureInputMonitorTests: XCTestCase {
  func testTracksSecureInputAndTheApplicationHoldingIt() {
    var snapshot = SecureInputMonitor.Snapshot(isEnabled: true, holderPID: 42)
    let monitor = SecureInputMonitor(probe: { snapshot }, appName: { $0 == 42 ? "Google Chrome" : nil })
    XCTAssertFalse(monitor.isEnabled)

    monitor.refresh()
    XCTAssertTrue(monitor.isEnabled)
    XCTAssertEqual(monitor.holderName, "Google Chrome")

    snapshot = SecureInputMonitor.Snapshot(isEnabled: false, holderPID: nil)
    monitor.refresh()
    XCTAssertFalse(monitor.isEnabled)
    XCTAssertNil(monitor.holderName)
  }

  func testUnknownHolderHasNoName() {
    let monitor = SecureInputMonitor(
      probe: { SecureInputMonitor.Snapshot(isEnabled: true, holderPID: nil) },
      appName: { _ in "Unexpected" }
    )
    monitor.refresh()
    XCTAssertTrue(monitor.isEnabled)
    XCTAssertNil(monitor.holderName)
  }

  func testOwnProcessIsNeverReportedAsTheHolder() {
    let monitor = SecureInputMonitor(
      probe: { SecureInputMonitor.Snapshot(isEnabled: true, holderPID: ProcessInfo.processInfo.processIdentifier) },
      appName: { _ in "MultiRam" }
    )
    monitor.refresh()
    XCTAssertNil(monitor.holderName)
  }

  func testSystemSnapshotCanBeReadInsideTheSandbox() {
    let snapshot = SecureInputMonitor.systemSnapshot()
    if !snapshot.isEnabled {
      XCTAssertNil(snapshot.holderPID)
    }
  }
}
