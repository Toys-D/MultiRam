import AppKit
import XCTest
@testable import MultiRam

final class PasteAccessTests: XCTestCase {
  func testGrantedWhenEventsCanBePosted() {
    XCTAssertEqual(Accessibility.access(canPostEvents: true, isTrusted: true, sawAccessibilityOff: false), .granted)
    XCTAssertEqual(Accessibility.access(canPostEvents: true, isTrusted: false, sawAccessibilityOff: true), .granted)
  }

  func testNeedsPermissionWhenAccessibilityIsOff() {
    XCTAssertEqual(
      Accessibility.access(canPostEvents: false, isTrusted: false, sawAccessibilityOff: true), .needsPermission
    )
  }

  // WindowServer keeps the denial it cached while Accessibility was off until the process quits.
  func testNeedsRelaunchWhenAccessibilityWasTurnedOnAfterADenial() {
    XCTAssertEqual(
      Accessibility.access(canPostEvents: false, isTrusted: true, sawAccessibilityOff: true), .needsRelaunch
    )
  }

  // A process that never saw Accessibility off got a real denial; relaunching would only repeat it.
  func testDoesNotOfferARelaunchForADenialWithAccessibilityOn() {
    XCTAssertEqual(
      Accessibility.access(canPostEvents: false, isTrusted: true, sawAccessibilityOff: false), .needsPermission
    )
  }
}

final class AccessibilityTextTests: XCTestCase {
  func testNamesThePaneTheWayThisMacOSVersionDoes() {
    XCTAssertEqual(Accessibility.paneNameKey(majorVersion: 26), "accessibility_pane")
    XCTAssertEqual(Accessibility.paneNameKey(majorVersion: 27), "accessibility_pane_macos27")
    XCTAssertEqual(Accessibility.paneNameKey(majorVersion: 28), "accessibility_pane_macos27")
  }

  func testAlertTextsHaveNoPlaceholdersLeft() {
    for key in ["accessibility_alert_comment", "accessibility_relaunch_comment"] {
      let text = Accessibility.localized(key)
      XCTAssertFalse(text.contains("{"), text)
      XCTAssertNotEqual(text, key)
    }
  }

  func testAboutNamesTheDeveloper() {
    let credits = About.creditsText
    XCTAssertTrue(credits.hasPrefix("MultiRam History"))
    for part in ["Dmitry Kohan", "Pixmap Labs", "pixmap1981@gmail.com", "github.com/Toys-D"] {
      XCTAssertTrue(credits.contains(part), part)
    }
  }
}

@MainActor
final class AccessibilityGrantWatcherTests: XCTestCase {
  private var trusted = false
  private var canPost = false
  private var relaunches = 0
  private var now = Date(timeIntervalSinceReferenceDate: 0)

  private func makeWatcher(timeout: TimeInterval = 60) -> AccessibilityGrantWatcher {
    AccessibilityGrantWatcher(
      interval: 3600,
      timeout: timeout,
      isTrusted: { [unowned self] in trusted },
      canPostEvents: { [unowned self] in canPost },
      relaunch: { [unowned self] in relaunches += 1 },
      now: { [unowned self] in now }
    )
  }

  func testRelaunchesOnceAccessibilityIsTurnedOn() {
    let watcher = makeWatcher()
    watcher.start()
    XCTAssertTrue(watcher.isWatching)

    watcher.tick()
    XCTAssertEqual(relaunches, 0)

    trusted = true
    watcher.tick()
    watcher.tick()

    XCTAssertEqual(relaunches, 1)
    XCTAssertFalse(watcher.isWatching)
  }

  func testDoesNotRelaunchWhenPastingAlreadyWorksAfterTheGrant() {
    let watcher = makeWatcher()
    watcher.start()
    trusted = true
    canPost = true
    watcher.tick()
    XCTAssertEqual(relaunches, 0)
    XCTAssertFalse(watcher.isWatching)
  }

  // The alert is modal; the user may turn access on before closing it.
  func testRelaunchesWhenAccessWasTurnedOnWhileTheAlertWasOpen() {
    trusted = true
    let watcher = makeWatcher()
    watcher.start()
    watcher.tick()
    XCTAssertEqual(relaunches, 1)
    XCTAssertFalse(watcher.isWatching)
  }

  func testStopsWatchingAfterTheTimeout() {
    let watcher = makeWatcher(timeout: 60)
    watcher.start()
    now += 61
    watcher.tick()
    XCTAssertFalse(watcher.isWatching)

    trusted = true
    watcher.tick()
    XCTAssertEqual(relaunches, 0)
  }

  func testStartingAgainExtendsTheTimeout() {
    let watcher = makeWatcher(timeout: 60)
    watcher.start()
    now += 50
    watcher.start()
    now += 50
    watcher.tick()
    XCTAssertTrue(watcher.isWatching)
  }
}

final class AppRelauncherTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suiteName = "AppRelauncherTests"
  private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

  override func setUp() {
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
  }

  func testTakesAFreshRequestOnce() {
    defaults.set(["pid": 4242, "date": now.addingTimeInterval(-2)], forKey: AppRelauncher.requestKey)
    XCTAssertEqual(AppRelauncher.takeRequest(from: defaults, now: now), 4242)
    XCTAssertNil(AppRelauncher.takeRequest(from: defaults, now: now))
  }

  // A request left by a relaunch that never happened must not make a later launch wait or skip a relaunch.
  func testIgnoresAndRemovesAStaleRequest() {
    defaults.set(["pid": 4242, "date": now.addingTimeInterval(-60)], forKey: AppRelauncher.requestKey)
    XCTAssertNil(AppRelauncher.takeRequest(from: defaults, now: now))
    XCTAssertNil(defaults.object(forKey: AppRelauncher.requestKey))
  }

  func testIgnoresAMalformedRequest() {
    defaults.set(["pid": "x"], forKey: AppRelauncher.requestKey)
    XCTAssertNil(AppRelauncher.takeRequest(from: defaults, now: now))
    XCTAssertNil(defaults.object(forKey: AppRelauncher.requestKey))
  }

  func testWaitsUntilThePreviousInstanceQuits() {
    var remaining = 3
    var checked: [pid_t] = []
    let finished = AppRelauncher.waitForProcess(
      77,
      timeout: 10,
      isRunning: { pid in checked.append(pid); remaining -= 1; return remaining >= 0 },
      sleep: { _ in }
    )
    XCTAssertTrue(finished)
    XCTAssertEqual(checked, [77, 77, 77, 77])
  }

  func testGivesUpWhenThePreviousInstanceDoesNotQuit() {
    var slept: TimeInterval = 0
    let finished = AppRelauncher.waitForProcess(77, timeout: 1, isRunning: { _ in true }, sleep: { slept += $0 })
    XCTAssertFalse(finished)
    XCTAssertEqual(slept, 1, accuracy: 0.11)
  }

  func testAProcessThatExistsIsRunning() {
    XCTAssertTrue(AppRelauncher.isProcessRunning(ProcessInfo.processInfo.processIdentifier))
    XCTAssertFalse(AppRelauncher.isProcessRunning(pid_t(Int32.max)))
  }

  @MainActor
  func testRelaunchStartsANewInstanceAndQuitsAfterItLaunched() throws {
    var configuration: NSWorkspace.OpenConfiguration?
    var openedURL: URL?
    var completion: ((Error?) -> Void)?
    var terminated = false
    var markedAsRelaunch = false
    let quit = expectation(description: "terminate")
    AppRelauncher.relaunch(
      bundleURL: URL(fileURLWithPath: "/Applications/MultiRam.app"),
      processIdentifier: 321,
      defaults: defaults,
      now: now,
      open: { url, config, done in openedURL = url; configuration = config; completion = done },
      terminate: {
        terminated = true
        markedAsRelaunch = AppRelauncher.isTerminatingForRelaunch
        quit.fulfill()
      },
      failed: { _ in XCTFail("unexpected failure") }
    )

    XCTAssertEqual(openedURL?.path, "/Applications/MultiRam.app")
    XCTAssertEqual(configuration?.createsNewApplicationInstance, true)
    XCTAssertEqual(configuration?.activates, false)
    XCTAssertFalse(terminated, "Quitting before the new instance starts would leave no MultiRam running")

    // NSWorkspace calls back on a background queue.
    let done = try XCTUnwrap(completion)
    DispatchQueue.global().async { done(nil) }
    wait(for: [quit], timeout: 2)
    XCTAssertTrue(terminated)
    // applicationWillTerminate skips "Clear history on quit" while this is set.
    XCTAssertTrue(markedAsRelaunch)
    XCTAssertFalse(AppRelauncher.isTerminatingForRelaunch, "A cancelled termination must not skip a later real quit")
    XCTAssertEqual(AppRelauncher.takeRequest(from: defaults, now: now.addingTimeInterval(1)), 321)
  }

  @MainActor
  func testRelaunchKeepsRunningWhenTheNewInstanceFailsToStart() throws {
    var completion: ((Error?) -> Void)?
    var terminated = false
    var failure: Error?
    let reported = expectation(description: "failure reported")
    AppRelauncher.relaunch(
      bundleURL: URL(fileURLWithPath: "/Applications/MultiRam.app"),
      processIdentifier: 321,
      defaults: defaults,
      now: now,
      open: { _, _, done in completion = done },
      terminate: { terminated = true },
      failed: { failure = $0; reported.fulfill() }
    )

    let done = try XCTUnwrap(completion)
    DispatchQueue.global().async { done(CocoaError(.fileNoSuchFile)) }
    wait(for: [reported], timeout: 2)
    XCTAssertFalse(terminated)
    XCTAssertFalse(AppRelauncher.isTerminatingForRelaunch)
    XCTAssertNotNil(failure)
    XCTAssertNil(defaults.object(forKey: AppRelauncher.requestKey), "The next normal launch must not wait")
  }
}
