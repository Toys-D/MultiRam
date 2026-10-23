import Carbon
import XCTest

// swiftlint:disable file_length
// swiftlint:disable type_body_length
class MultiRamUITests: XCTestCase {
  let app = XCUIApplication()
  let pasteboard = NSPasteboard.general
  private var savedPasteboardItems: [NSPasteboardItem] = []

  let copy1 = UUID().uuidString
  let copy2 = UUID().uuidString
  let copy3 = UUID().uuidString

  // https://hetima.github.io/fucking_nsimage_syntax
  let image1 = NSImage(named: "NSAddTemplate")!
  let image2 = NSImage(named: "NSBluetoothTemplate")!

  let fixtureDirectory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var file1: URL { fixtureDirectory.appendingPathComponent("file1.txt") }
  var file2: URL { fixtureDirectory.appendingPathComponent("file2.txt") }

  let rtf1 = NSAttributedString(string: "foo").rtf(
    from: NSRange(0...2),
    documentAttributes: [:]
  )
  let rtf2 = NSAttributedString(string: "bar").rtf(
    from: NSRange(0...2),
    documentAttributes: [:]
  )

  let html1 = "<a href='#'>foo</a>".data(using: .utf8)
  let html2 = "<a href='#'>bar</a>".data(using: .utf8)

  let imageType = NSPredicate(
    format: "elementType == %lu",
    argumentArray: [XCUIElement.ElementType.image.rawValue]
  )

  var items: XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "copy-history-item")
  }

  var expandedDetail: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "history-item-detail").firstMatch
  }

  var itemTitles: [String] {
    items.allElementsBoundByIndex
      .sorted(by: { $0.frame.origin.y < $1.frame.origin.y })
      .compactMap { $0.value as? String }
  }

  override func setUp() {
    super.setUp()

    savedPasteboardItems = (pasteboard.pasteboardItems ?? []).map { original in
      let copy = NSPasteboardItem()
      for type in original.types {
        if let data = original.data(forType: type) { copy.setData(data, forType: type) }
      }
      return copy
    }
    try? FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)

    try? "Hello world".write(to: file1, atomically: true, encoding: .utf8)
    try? "Hello world".write(to: file2, atomically: true, encoding: .utf8)

    // Argument-domain defaults keep tests independent of the user's saved shortcut.
    app.launchArguments = [
      "enable-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      "-KeyboardShortcuts_popup", "{\"carbonKeyCode\":8,\"carbonModifiers\":768}",
      "-suppressClearAlert", "NO", "-pasteByDefault", "NO"
    ]
    app.launch()

    copyToClipboard(copy2)
    copyToClipboard(copy1)

  }

  override func tearDown() {
    super.tearDown()
    app.terminate()
    pasteboard.clearContents()
    pasteboard.writeObjects(savedPasteboardItems)
    savedPasteboardItems = []
    try? FileManager.default.removeItem(at: fixtureDirectory)
  }

  func testPopupWithHotkey() throws {
    popUpWithHotkey()
    assertExists(items[copy1])
    assertExists(items[copy2])
    assertHistoryToolbar()
  }

  func testPopupStaysOnScreenAtBottom() throws {
    app.terminate()
    app.launchArguments += [
      "-popupPosition", "cursor", "-windowSize", "[450,39]",
      "-imageMaxHeight", "100"
    ]
    app.launch()

    for color in [NSColor.systemBlue, NSColor.systemRed] {
      let image = NSImage(size: NSSize(width: 320, height: 160))
      image.lockFocus()
      color.setFill()
      NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
      image.unlockFocus()
      copyToClipboard(image)
    }

    let screen = try XCTUnwrap(NSScreen.main).visibleFrame
    let primaryTop = try XCTUnwrap(NSScreen.screens.first).frame.maxY
    let originalMouse = NSEvent.mouseLocation
    let cursor = NSPoint(x: screen.midX, y: screen.minY + 10)
    func moveMouse(to point: NSPoint) {
      let statusItem = app.statusItems.firstMatch
      let origin = statusItem.frame.origin
      statusItem.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: point.x - origin.x, dy: primaryTop - point.y - origin.y))
        .hover()
    }
    defer { moveMouse(to: originalMouse) }
    moveMouse(to: cursor)
    XCTAssertEqual(NSEvent.mouseLocation.y, cursor.y, accuracy: 2)

    reopenHistoryAtCursor()

    let frame = app.dialogs.firstMatch.frame
    let visible = NSRect(x: screen.minX, y: primaryTop - screen.maxY, width: screen.width, height: screen.height)
    XCTAssertGreaterThan(frame.height, 150)
    XCTAssertGreaterThanOrEqual(frame.minX, visible.minX - 1)
    XCTAssertGreaterThanOrEqual(frame.minY, visible.minY - 1)
    XCTAssertLessThanOrEqual(frame.maxX, visible.maxX + 1)
    XCTAssertLessThanOrEqual(frame.maxY, primaryTop - cursor.y + 1)
    let imageRows = items.matching(imageType).allElementsBoundByIndex
    XCTAssertEqual(imageRows.count, 2)
    for image in imageRows {
      XCTAssertGreaterThan(image.frame.height, 20)
      XCTAssertTrue(frame.contains(image.frame), "The complete image row must be visible, not clipped below the header")
    }

    let screenshot = XCTAttachment(screenshot: app.dialogs.firstMatch.screenshot())
    screenshot.name = "History opens above the cursor near the bottom edge"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    app.typeKey(.escape, modifierFlags: [])
    moveMouse(to: NSPoint(x: screen.midX, y: screen.midY))
    reopenHistoryAtCursor()
    let reopenedFrame = app.dialogs.firstMatch.frame
    XCTAssertEqual(reopenedFrame.height, frame.height, accuracy: 1)
    XCTAssertTrue(visible.contains(reopenedFrame))
    for image in items.matching(imageType).allElementsBoundByIndex {
      XCTAssertTrue(reopenedFrame.contains(image.frame), "Reopening must preserve the complete image rows")
    }
  }

  private func reopenHistoryAtCursor() {
    // Reopen uses the same popup placement as the hotkey without global event-injection permissions.
    let appURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("MultiRam.app")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    let reopened = expectation(description: "Reopen the history window")
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
      XCTAssertNil(error)
      reopened.fulfill()
    }
    wait(for: [reopened], timeout: 5)
    waitUntilPoppedUp()
    usleep(300_000) // Allow asynchronous thumbnail layout to finish.
  }

  func testCloseWithHotkey() throws {
    popUpWithMouse()
    assertExists(items[copy1])
    simulatePopupHotkey()
    assertNotExists(items[copy1])
  }

  func testPopupWithMenubar() {
    popUpWithMouse()
    assertExists(items[copy1])
    assertExists(items[copy2])
    assertHistoryToolbar()
  }

  func testStatusMenuOpensPreferences() {
    app.statusItems.firstMatch.click()
    assertExists(app.menuItems["Show History"])
    assertExists(app.menuItems["Preferences…"])
    assertExists(app.menuItems["About"])
    assertExists(app.menuItems["Quit"])
    assertNotExists(items[copy1])

    app.menuItems["Preferences…"].click()
    assertExists(app.windows.buttons["General"])
    assertNotExists(items[copy1])
  }

  func testNewCopyIsAdded() {
    popUpWithMouse()
    let copy3 = UUID().uuidString
    copyToClipboard(copy3)
    assertExists(items[copy3])
    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertExists(items[copy2])
  }

  func testSearch() {
    popUpWithMouse()
    search(copy2)
    assertSearchFieldValue(copy2)
    assertExists(app.staticTexts[copy2])
    assertNotExists(items[copy1])
  }

  func testSearchFiles() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()
    search(file2.lastPathComponent)
    assertExists(fileItem(file2))
    assertNotExists(fileItem(file1))
  }

  func testCopyWithClick() {
    popUpWithMouse()
    items[copy2].firstMatch.click()
    assertPasteboardStringEquals(copy2)
  }

  func testAutomaticPasteExplainsMissingPermission() throws {
    app.terminate()
    app.launchArguments += ["-pasteByDefault", "YES"]
    app.launch()
    copyToClipboard(copy2)
    popUpWithMouse()
    items[copy2].firstMatch.click()
    let alert = app.dialogs["paste-permission-required"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5),
                  "Run this test with event-posting permission denied for the test build")
    assertPasteboardStringEquals(copy2)
    // The Touch Bar mirrors alert buttons, so look for them inside the alert only.
    XCTAssertTrue(alert.buttons["Open System Settings"].exists)
    alert.buttons["Later"].click()
    XCTAssertFalse(alert.exists)
  }

  func testCopyWithEnter() {
    popUpWithMouse()
    hover(items[copy2].firstMatch)
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  func testNumberShortcutsDoNotCopy() {
    popUpWithMouse()
    for number in 1...9 {
      simulateNumberShortcut(number)
    }
    assertExists(items[copy1])
    assertExists(items[copy2])
    assertPasteboardStringEquals(copy1)
  }

  func testNumberShortcutsDoNotCopySearchResults() {
    popUpWithMouse()
    search(copy2)
    assertSearchFieldValue(copy2)
    assertExists(items[copy2])
    simulateNumberShortcut(1)
    XCTAssertTrue(items[copy2].waitForExistence(timeout: 3), app.debugDescription)
    assertPasteboardStringEquals(copy1)
  }

  func testPinAndUnpinWithRowButton() {
    popUpWithMouse()
    let window = app.dialogs.firstMatch
    let originalWidth = window.frame.width
    let pinButtons = app.buttons.matching(identifier: "pin-history-item")
    let secondButton = pinButtons.allElementsBoundByIndex.sorted { $0.frame.midY < $1.frame.midY }[1]
    XCTAssertEqual(secondButton.label, "Pin")
    secondButton.click()

    assertExists(items[copy1])
    assertExists(items[copy2])
    assertPasteboardStringEquals(copy1)
    XCTAssertEqual(Array(itemTitles.prefix(2)), [copy2, copy1])

    let unpinButton = app.buttons["Unpin"].firstMatch
    assertExists(unpinButton)
    unpinButton.click()
    assertPasteboardStringEquals(copy1)
    XCTAssertEqual(Array(itemTitles.prefix(2)), [copy1, copy2])
    assertNotExists(app.buttons["Unpin"])
    XCTAssertEqual(window.frame.width, originalWidth, accuracy: 1)
  }

  func testPinImageImmediatelyAfterOpening() {
    copyToClipboard(image1)
    let clipboardChangeCount = pasteboard.changeCount
    reopenHistoryAtCursor()
    let window = app.dialogs.firstMatch
    let originalWidth = window.frame.width
    let pinButton = app.buttons.matching(identifier: "pin-history-item").allElementsBoundByIndex
      .min { $0.frame.minY < $1.frame.minY }!
    pinButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    assertExists(app.buttons["Unpin"])
    assertExists(items.matching(imageType).firstMatch)
    assertPasteboardDataEquals(image1.tiffRepresentation, forType: .tiff)
    XCTAssertEqual(pasteboard.changeCount, clipboardChangeCount)

    app.buttons["Unpin"].firstMatch.click()
    assertNotExists(app.buttons["Unpin"])
    assertPasteboardDataEquals(image1.tiffRepresentation, forType: .tiff)
    XCTAssertEqual(pasteboard.changeCount, clipboardChangeCount)
    XCTAssertEqual(window.frame.width, originalWidth, accuracy: 1)
  }

  func testHistoryDoesNotOpenPreviewAfterHovering() {
    popUpWithMouse()
    let window = app.dialogs.firstMatch
    let originalWidth = window.frame.width
    hover(items[copy2].firstMatch)
    usleep(2_000_000)
    XCTAssertEqual(window.frame.width, originalWidth, accuracy: 1)
    XCTAssertEqual(app.buttons.matching(identifier: "pin-history-item").count, 2)
  }

  func testWindowDragsFromTitleAndPinStillWorks() {
    popUpWithMouse()
    let window = app.dialogs.firstMatch
    let originalFrame = window.frame
    let title = app.staticTexts["MultiRam"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let destination = title.withOffset(CGVector(dx: -40, dy: 40))
    title.press(forDuration: 0.1, thenDragTo: destination)
    XCTAssertEqual(window.frame.minX, originalFrame.minX - 40, accuracy: 3)
    XCTAssertEqual(window.frame.minY, originalFrame.minY + 40, accuracy: 3)
    XCTAssertEqual(window.frame.size, originalFrame.size)

    app.buttons.matching(identifier: "pin-history-item").firstMatch.click()
    assertExists(app.buttons["Unpin"])
    assertPasteboardStringEquals(copy1)
  }

  func testCopyImage() {
    copyToClipboard(image2)
    copyToClipboard(image1)
    popUpWithMouse()
    items.matching(imageType).allElementsBoundByIndex[1].click()
    assertPasteboardDataCountEquals(image2.tiffRepresentation!.count, forType: .tiff)
  }

  func testCopyFile() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()

    XCTAssertEqual(itemTitles[0...1], [
      file1.absoluteString.removingPercentEncoding!,
      file2.absoluteString.removingPercentEncoding!
    ])

    fileItem(file2).click()
    assertPasteboardStringEquals(file2.absoluteString, forType: .fileURL)
  }

  func testCopyRTF() {
    copyToClipboard(rtf2, .rtf)
    copyToClipboard(rtf1, .rtf)
    popUpWithHotkey()
    XCTAssertEqual(itemTitles[0...1], ["foo", "bar"])

    app.staticTexts["bar"].firstMatch.click()
    XCTAssertEqual(pasteboard.data(forType: .rtf), rtf2)
  }

  func testCopyHTML() {
    copyToClipboard(html2, .html)
    copyToClipboard(html1, .html)
    popUpWithMouse()
    XCTAssertEqual(itemTitles[0...1], ["foo", "bar"])

    items["bar"].firstMatch.click()
    assertPasteboardDataEquals(html2, forType: .html)
  }

  func testDownArrow() {
    popUpWithMouse()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  func testUpArrow() {
    popUpWithMouse()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.upArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy1)
  }

  func testControlJ() {
    popUpWithMouse()
    app.typeKey("j", modifierFlags: [.control])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  func testControlK() {
    popUpWithMouse()
    app.typeKey("j", modifierFlags: [.control])
    app.typeKey("k", modifierFlags: [.control])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy1)
  }

  func testDeleteEntry() {
    popUpWithMouse()
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(items[copy1])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(items[copy1])
  }

  func testDeleteEntryDuringSearch() {
    popUpWithMouse()
    search(copy2)
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(items[copy2])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(items[copy2])
  }

  func testClear() {
    popUpWithMouse()
    pin(copy2)
    app.buttons["clear-history"].click()
    confirmClear()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertExists(items[copy2])
  }

  func testClearDuringSearch() {
    popUpWithMouse()
    search(copy2)
    app.buttons["clear-history"].click()
    confirmClear()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertNotExists(items[copy2])
  }

  func testClearAll() {
    popUpWithMouse()
    pin(copy2)
    XCUIElement.perform(withKeyModifiers: [.shift]) {
      app.buttons["clear-history"].click()
    }
    confirmClear()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertNotExists(items[copy2])
  }

  func testPin() {
    popUpWithMouse()
    pin(copy2)
    XCTAssertEqual(itemTitles[0...1], [copy2, copy1])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    XCTAssertEqual(itemTitles[0...1], [copy2, copy1])
  }

  func testPinDuringSearch() {
    popUpWithMouse()
    search(copy2)
    pin(copy2)
    assertSearchFieldValue("")
    XCTAssertEqual(itemTitles[0...1], [copy2, copy1])
  }

  func testUnpin() {
    popUpWithMouse()
    pin(copy2)
    pin(copy2)
    XCTAssertEqual(itemTitles[0...1], [copy1, copy2])
  }

  func testRemoveLastWordFromSearchWithControlW() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey("w", modifierFlags: [.control])
    assertSearchFieldValue("foo ")
  }

  func testPasteToSearch() {
    popUpWithMouse()
    app.typeKey("v", modifierFlags: [.command])
    waitForSearch()
    assertSearchFieldValue(copy1)
    assertExists(items[copy1])
    assertNotExists(items[copy2])
  }

  func testDisablesOnOptionClickingMenubarIcon() {
    XCUIElement.perform(withKeyModifiers: .option) {
      app.statusItems.firstMatch.click()
    }

    let copy3 = UUID().uuidString
    let copy4 = UUID().uuidString
    copyToClipboard(copy3)
    copyToClipboard(copy4)

    popUpWithMouse()
    assertNotExists(items[copy3])
    assertNotExists(items[copy4])

    app.typeKey(.escape, modifierFlags: [])
    XCUIElement.perform(withKeyModifiers: .option) {
      app.statusItems.firstMatch.click()
    }
  }

  func testDisablesOnlyForNextCopyOnOptionShiftClickingMenubarIcon() {
    XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
      app.statusItems.firstMatch.click()
    }

    let copy3 = UUID().uuidString
    let copy4 = UUID().uuidString
    copyToClipboard(copy3)
    copyToClipboard(copy4)

    popUpWithMouse()
    assertNotExists(items[copy3])
    assertExists(items[copy4])
  }

  func testCreatesNewCopyOnEnterWhenSearchResultsAreEmpty() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey(.return, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: .string), "foo bar")
    assertExists(items["foo bar"])
  }

  func testOpenAndClose() throws {
    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Release the 'C' key but keep the popup open.
    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cUp.flags = [.maskCommand, .maskShift]
    cUp.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Release the 'Shift' key and assert that the popup remains open - "normal" mode.
    let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftUp.flags = [.maskCommand] // Command remains active, Shift released
    shiftUp.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Release the 'CMD' key and assert that the popup remains open - "normal" mode.
    let commandUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false)!
    commandUp.flags = []
    commandUp.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Press shortcut again and assert the window closes
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    assertPopupDismissed()
  }

  func testOpenAndSelectSecondItem() throws {
    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cUp.flags = [.maskCommand, .maskShift]
    cUp.post(tap: .cghidEventTap)

    // Press C 1 more time while keeping the modifier keys pressed
    cDown.post(tap: .cghidEventTap)

    // Release all modifiers keys and assert that the popup closes.
    let modifiersUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    modifiersUp.flags = []
    modifiersUp.post(tap: .cghidEventTap)

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  func testOpenAndSelectThirdItem() throws {
    copyToClipboard(copy3)

    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cUp.flags = [.maskCommand, .maskShift]
    cUp.post(tap: .cghidEventTap)

    // Press C 2 more times while keeping the modifier keys pressed
    cDown.post(tap: .cghidEventTap)
    cUp.post(tap: .cghidEventTap)
    cDown.post(tap: .cghidEventTap)

    // Release all modifiers keys and assert that the popup closes.
    let modifiersUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    modifiersUp.flags = []
    modifiersUp.post(tap: .cghidEventTap)

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  func testOpenAndSelectThirdItemRepeatedPress() throws {
    copyToClipboard(copy3)

    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Press C 2 more times while keeping the modifier keys pressed
    cDown.post(tap: .cghidEventTap)
    cDown.post(tap: .cghidEventTap)

    // Release all modifiers keys and assert that the popup closes.
    let modifiersUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    modifiersUp.flags = []
    modifiersUp.post(tap: .cghidEventTap)

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  func testTogglePopupAndCloseOnClickOutside() {
    popUpWithHotkey()

    // Click outside the popup to close it
    let statusBar = app.statusItems.firstMatch
    let coordinate = statusBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 10.0))
    coordinate.click()
    assertNotExists(items[copy1])

    // Assert that the hotkeys still work
    popUpWithHotkey()

    simulatePopupHotkey()
    assertPopupDismissed()
  }

  func testExpandOpensSidePanelWithFullText() {
    let longText = (1...12).map { "Line \($0) of \(copy3)" }.joined(separator: "\n")
    copyToClipboard(longText)
    popUpWithMouse()
    let window = app.dialogs.firstMatch
    let listFrame = window.frame

    // Short single-line items have nothing to reveal, so only the long copy gets a button.
    let expandButtons = app.buttons.matching(identifier: "expand-history-item")
    XCTAssertEqual(expandButtons.count, 1)
    XCTAssertEqual(expandButtons.firstMatch.label, "Expand")
    expandButtons.firstMatch.click()

    let detail = expandedDetail
    assertExists(detail)
    XCTAssertEqual(detail.value as? String, longText)
    // The window widens by the panel; the list stays where it was and the popup stays open.
    XCTAssertGreaterThan(window.frame.width, listFrame.width + 300)
    XCTAssertTrue(detail.frame.minX >= listFrame.maxX - 1 || detail.frame.maxX <= listFrame.minX + 1)
    assertExists(items[copy1])

    let collapseButton = app.buttons["Collapse"].firstMatch
    assertExists(collapseButton)
    collapseButton.click()
    assertNotExists(detail)
    XCTAssertEqual(window.frame.width, listFrame.width, accuracy: 1)
  }

  func testSidePanelSwitchesBetweenItems() {
    let first = "first of \(copy3)\nsecond line"
    let second = "second of \(copy3)\nanother line"
    copyToClipboard(first)
    copyToClipboard(second)
    popUpWithMouse()

    let buttons = app.buttons.matching(identifier: "expand-history-item")
    XCTAssertEqual(buttons.count, 2)
    let sortedButtons = buttons.allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }
    sortedButtons[0].click()
    assertExists(expandedDetail)
    XCTAssertEqual(expandedDetail.value as? String, second)

    app.buttons.matching(identifier: "expand-history-item").allElementsBoundByIndex
      .sorted { $0.frame.minY < $1.frame.minY }[1].click()
    assertExists(expandedDetail)
    XCTAssertEqual(expandedDetail.value as? String, first)
    XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "history-item-detail").count, 1)
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Collapse")).count, 1)
  }

  func testSidePanelClosesWhenPopupCloses() {
    copyToClipboard("first line of \(copy3)\nsecond line")
    popUpWithMouse()
    let window = app.dialogs.firstMatch
    let listWidth = window.frame.width
    app.buttons.matching(identifier: "expand-history-item").firstMatch.click()
    assertExists(expandedDetail)

    app.typeKey(.escape, modifierFlags: [])
    assertPopupDismissed()

    popUpWithMouse()
    assertExists(items[copy1])
    assertNotExists(expandedDetail)
    XCTAssertEqual(window.frame.width, listWidth, accuracy: 1)
  }

  func testSidePanelShowsImageLargerThanThumbnail() {
    let image = NSImage(size: NSSize(width: 320, height: 160))
    image.lockFocus()
    NSColor.systemGreen.setFill()
    NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
    image.unlockFocus()
    copyToClipboard(image)
    popUpWithMouse()

    let thumbnail = items.matching(imageType).firstMatch
    assertExists(thumbnail)
    let thumbnailHeight = thumbnail.frame.height
    app.buttons.matching(identifier: "expand-history-item").firstMatch.click()

    let detail = expandedDetail
    assertExists(detail)
    XCTAssertGreaterThan(detail.frame.height, thumbnailHeight)
    XCTAssertEqual(detail.frame.width, 320, accuracy: 2)
    assertExists(thumbnail)
  }

  func testImagePanelOffersOpenWithApplications() {
    let image = NSImage(size: NSSize(width: 320, height: 160))
    image.lockFocus()
    NSColor.systemOrange.setFill()
    NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
    image.unlockFocus()
    copyToClipboard(image)
    popUpWithMouse()

    app.buttons.matching(identifier: "expand-history-item").firstMatch.click()
    assertExists(expandedDetail)
    let openButtons = app.buttons.matching(identifier: "open-with-app")
    assertExists(openButtons.firstMatch)
    XCTAssertTrue(openButtons.firstMatch.label.hasPrefix("Open in "), openButtons.firstMatch.label)
    XCTAssertLessThanOrEqual(openButtons.count, 4)

    let more = app.descendants(matching: .any).matching(identifier: "open-with-more").firstMatch
    assertExists(more)
    more.click()
    assertExists(app.menuItems["Other Application…"])
    assertExists(app.menuItems["Show in Finder"])
    app.typeKey(.escape, modifierFlags: [])
  }

  func testTextPanelHasNoOpenWithBar() {
    copyToClipboard("first line of \(copy3)\nsecond line")
    popUpWithMouse()
    app.buttons.matching(identifier: "expand-history-item").firstMatch.click()
    assertExists(expandedDetail)
    assertNotExists(app.buttons.matching(identifier: "open-with-app").firstMatch)
  }

  private func popUpWithHotkey() {
    simulatePopupHotkey()
    waitUntilPoppedUp()
  }

  private func popUpWithMouse() {
    app.statusItems.firstMatch.click()
    let showHistory = app.menuItems["Show History"]
    assertExists(showHistory)
    showHistory.click()
    waitUntilPoppedUp()
  }

  private func assertHistoryToolbar() {
    let clearButton = app.buttons["clear-history"]
    assertExists(clearButton)
    XCTAssertLessThan(abs(clearButton.frame.midY - app.textFields.firstMatch.frame.midY), 20)
    assertNotExists(app.staticTexts["Clear"])
    assertNotExists(app.staticTexts["Preferences…"])
    assertNotExists(app.staticTexts["About"])
    assertNotExists(app.staticTexts["Quit"])
  }

  private func simulatePopupHotkey() {
    let commandDown = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: true)!
    let commandUp = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false)!
    let shiftDown = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: true)!
    let shiftUp = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftDown.flags = [.maskCommand]
    shiftUp.flags = [.maskCommand]
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cDown.flags = [.maskCommand, .maskShift]
    cUp.flags = [.maskCommand, .maskShift]
    commandDown.post(tap: .cghidEventTap)
    shiftDown.post(tap: .cghidEventTap)
    cDown.post(tap: .cghidEventTap)
    cUp.post(tap: .cghidEventTap)
    shiftUp.post(tap: .cghidEventTap)
    commandUp.post(tap: .cghidEventTap)
  }

  private func simulateNumberShortcut(_ number: Int) {
    // typeKey activates the app for unhandled shortcuts, dismissing its nonactivating panel.
    // Post keyboard events directly, as in the global-hotkey tests.
    let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    for keyDown in [true, false] {
      let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCodes[number - 1], keyDown: keyDown)!
      event.flags = .maskCommand
      event.post(tap: .cghidEventTap)
    }
    usleep(100_000)
  }

  private func waitUntilPoppedUp() {
    if !app.staticTexts.firstMatch.waitForExistence(timeout: 3) {
      XCTFail("MultiRam did not pop up")
    }
  }

  private func assertPopupDismissed() {
    if !app.staticTexts.firstMatch.waitForNonExistence(timeout: 3) {
      XCTFail("MultiRam did not dismiss")
    }
  }

  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: .string)
    waitTillClipboardCheck()
  }

  private func copyToClipboard(_ content: NSImage) {
    pasteboard.clearContents()
    pasteboard.setData(content.tiffRepresentation, forType: .tiff)
    waitTillClipboardCheck()
  }

  private func copyToClipboard(_ content: URL) {
    pasteboard.clearContents()
    pasteboard.setData(content.dataRepresentation, forType: .fileURL)
    // WTF: The subsequent writes to pasteboard are not
    // visible unless we explicitly read the last one?!
    pasteboard.string(forType: .fileURL)
    waitTillClipboardCheck()
  }

  private func fileItem(_ url: URL) -> XCUIElement {
    let title = url.absoluteString.removingPercentEncoding ?? url.absoluteString
    // XCTest's identifier subscript rejects strings longer than 128 characters.
    return items.matching(NSPredicate(format: "value == %@ OR label == %@", title, title)).firstMatch
  }

  private func copyToClipboard(_ content: Data?, _ type: NSPasteboard.PasteboardType) {
    pasteboard.clearContents()
    pasteboard.setData(content, forType: type)
    waitTillClipboardCheck()
  }

  // Default interval for MultiRam to check clipboard is 1 second
  private func waitTillClipboardCheck() {
    usleep(1_500_000)
  }

  private func pin(_ title: String) {
    hover(items[title].firstMatch)
    app.typeKey("p", modifierFlags: [.option])
    usleep(1_500_000)
  }

  private func hover(_ element: XCUIElement) {
    element.hover()
    usleep(20000)
  }

  private func search(_ string: String) {
    // NOTE: app.typeText is broken in Sonoma and causes some
    //       Chars to be submitted with a .command mask (e.g. 'p', 'k' or 'j')
    string.forEach {
      app.typeKey("\($0)", modifierFlags: [])
    }
    waitForSearch()
  }

  private func waitForSearch() {
    // NOTE: This is a hack and is flaky.
    // Ideally we should wait for a proper condition to detect that search has settled down.
    usleep(500000)  // wait for search throttle
  }

  private func assertExists(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "exists = 1"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertNotExists(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "exists = 0"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertNotVisible(_ element: XCUIElement) {
    expectation(
      for: NSPredicate(format: "(exists = 0) || (isHittable = 0)"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertPasteboardDataEquals(
    _ expected: Data?, forType: NSPasteboard.PasteboardType = .string
  ) {
    let predicate = NSPredicate { (object, _) -> Bool in
      guard let copy = object as? Data else {
        return false
      }

      return self.pasteboard.data(forType: forType) == copy
    }
    expectation(for: predicate, evaluatedWith: expected)
    waitForExpectations(timeout: 3)
  }

  private func assertPasteboardDataCountEquals(
    _ expected: Int, forType: NSPasteboard.PasteboardType = .string
  ) {
    let predicate = NSPredicate { (object, _) -> Bool in
      guard let count = object as? Int else {
        return false
      }

      return self.pasteboard.data(forType: forType)!.count == count
    }
    expectation(for: predicate, evaluatedWith: expected)
    waitForExpectations(timeout: 3)
  }

  private func assertPasteboardStringEquals(
    _ expected: String?, forType: NSPasteboard.PasteboardType = .string
  ) {
    let predicate = NSPredicate { (object, _) -> Bool in
      guard let copy = object as? String else {
        return false
      }

      return self.pasteboard.string(forType: forType) == copy
    }
    expectation(for: predicate, evaluatedWith: expected)
    waitForExpectations(timeout: 3)
  }

  private func assertSearchFieldValue(_ string: String) {
    XCTAssertEqual(app.textFields.firstMatch.value as? String, string)
  }

  private func confirmClear() {
    let button = app.dialogs.firstMatch.buttons["Clear"].firstMatch
    expectation(for: NSPredicate(format: "isHittable = 1"), evaluatedWith: button)
    waitForExpectations(timeout: 3)
    button.click()
  }
}
// swiftlint:enable type_body_length
// swiftlint:enable file_length
