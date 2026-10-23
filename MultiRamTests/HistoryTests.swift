import XCTest
import Defaults
import SwiftData
@testable import MultiRam

@MainActor
class HistoryTests: XCTestCase {
  let savedSize = Defaults[.size]
  let savedSortBy = Defaults[.sortBy]
  let history = History.shared

  override func setUp() {
    super.setUp()
    history.clearAll()
    Defaults[.size] = 10
    Defaults[.sortBy] = .firstCopiedAt
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.size] = savedSize
    Defaults[.sortBy] = savedSortBy
  }

  func testDefaultIsEmpty() {
    XCTAssertEqual(history.items, [])
  }

  func testReleaseDefaultsMatchTheApprovedConfiguration() {
    XCTAssertTrue(Defaults.Keys.pasteByDefault.defaultValue)
    XCTAssertEqual(Defaults.Keys.imageMaxHeight.defaultValue, 100)
    XCTAssertEqual(Defaults.Keys.size.defaultValue, 22)
    XCTAssertEqual(Defaults.Keys.sortBy.defaultValue, .firstCopiedAt)
    XCTAssertEqual(Defaults.Keys.windowSize.defaultValue, NSSize(width: 450, height: 800))
    XCTAssertEqual(Defaults.Keys.popupPosition.defaultValue, .cursor)
    XCTAssertEqual(Defaults.Keys.menuIcon.defaultValue, .multiram)
    XCTAssertTrue(Defaults.Keys.showSearch.defaultValue)
    XCTAssertFalse(Defaults.Keys.showApplicationIcons.defaultValue)
  }

  func testAdding() {
    let first = add(historyItem("foo"))
    let second = add(historyItem("bar"))
    XCTAssertEqual(history.items, [second, first])
  }

  func testNumberShortcutsDoNotSelectHistoryItems() throws {
    for index in 1...9 {
      add(historyItem("copy \(index)"))
    }

    let numberKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    for (index, keyCode) in numberKeyCodes.enumerated() {
      let event = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command,
        timestamp: 0, windowNumber: 0, context: nil,
        characters: String(index + 1), charactersIgnoringModifiers: String(index + 1),
        isARepeat: false, keyCode: keyCode
      ))
      XCTAssertNil(history.item(forShortcut: event))
    }
    XCTAssertEqual(history.items.count, 9)
  }

  func testDeletingTheItemShownInTheSidePanelClosesIt() {
    let popup = AppState.shared.popup
    let item = add(historyItem("foo\nbar"))
    popup.toggleDetail(for: item)
    XCTAssertTrue(popup.detailItem === item)

    history.delete(item)

    XCTAssertNil(popup.detailItem)
  }

  func testClearingHistoryRunsTheClearHook() {
    var cleared = 0
    history.onClear = { cleared += 1 }
    defer { history.onClear = nil }
    add(historyItem("foo"))
    history.clear()
    history.clearAll()
    XCTAssertEqual(cleared, 2)
  }

  func testAddingSame() {
    let first = historyItem("foo")
    first.title = "xyz"
    first.application = "iTerm.app"
    let firstDecorator = add(first)
    first.pin = "f"

    let secondDecorator = add(historyItem("bar"))

    let third = historyItem("foo")
    third.application = "Xcode.app"
    add(third)

    XCTAssertEqual(history.items, [firstDecorator, secondDecorator])
    XCTAssertTrue(history.items[0].item.lastCopiedAt > history.items[0].item.firstCopiedAt)
    XCTAssertEqual(history.items[0].item.numberOfCopies, 2)
    XCTAssertEqual(history.items[0].item.pin, "f")
    XCTAssertEqual(history.items[0].item.title, "xyz")
    XCTAssertEqual(history.items[0].item.application, "iTerm.app")
  }

  func testAddingItemThatIsSupersededByExisting() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.rtf.rawValue,
        value: "two".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.application = "MultiRam.app"
    firstItem.contents = firstContents
    firstItem.title = firstItem.generateTitle()
    add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.application = "MultiRam.app"
    secondItem.contents = secondContents
    secondItem.title = secondItem.generateTitle()
    let second = add(secondItem)

    XCTAssertEqual(history.items, [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testAddingItemWithDifferentModifiedType() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "1".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.contents = firstContents
    add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "2".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.contents = secondContents
    let second = add(secondItem)

    XCTAssertEqual(history.items, [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testAddingItemFromMultiRam() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      )
    ]
    let first = HistoryItem()
    Storage.shared.context.insert(first)
    first.application = "Xcode.app"
    first.contents = firstContents
    add(first)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fromMultiRam.rawValue,
        value: "".data(using: .utf8)
      )
    ]
    let second = HistoryItem()
    Storage.shared.context.insert(second)
    second.application = "MultiRam.app"
    second.contents = secondContents
    let secondDecorator = add(second)

    XCTAssertEqual(history.items, [secondDecorator])
    XCTAssertEqual(history.items[0].item.application, "Xcode.app")
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testModifiedAfterCopying() {
    add(historyItem("foo"))

    let modifiedItem = historyItem("bar")
    modifiedItem.contents.append(HistoryItemContent(
      type: NSPasteboard.PasteboardType.modified.rawValue,
      value: String(Clipboard.shared.changeCount).data(using: .utf8)
    ))
    let modifiedItemDecorator = add(modifiedItem)

    XCTAssertEqual(history.items, [modifiedItemDecorator])
    XCTAssertEqual(history.items[0].text, "bar")
  }

  func testClearingUnpinned() {
    let pinned = add(historyItem("foo"))
    pinned.togglePin()
    add(historyItem("bar"))
    history.clear()
    XCTAssertEqual(history.items, [pinned])
  }

  func testClearingAll() {
    add(historyItem("foo"))
    history.clear()
    XCTAssertEqual(history.items, [])
  }

  func testMaxSize() {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 10)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[0]))
  }

  func testMaxSizeIgnoresPinned() {
    var items: [HistoryItemDecorator] = []

    let item = add(historyItem("0"))
    items.append(item)
    item.togglePin()

    for index in 1...11 {
      items.append(add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 11)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertTrue(history.items.contains(items[0]))
    XCTAssertFalse(history.items.contains(items[1]))
  }

  func testMaxSizeIsChanged() {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(add(historyItem(String(index))))
    }
    Defaults[.size] = 5
    add(historyItem("11"))

    XCTAssertEqual(history.items.count, 5)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[5]))
  }

  func testRemoving() {
    let foo = add(historyItem("foo"))
    let bar = add(historyItem("bar"))
    history.delete(foo)
    XCTAssertEqual(history.items, [bar])
  }

  func testCopyingPinnedItemKeepsIdentityAndHistoryLimit() throws {
    Defaults[.size] = 2
    let pinned = add(historyItem("pinned"))
    pinned.togglePin()
    let first = add(historyItem("first"))
    let second = add(historyItem("second"))
    let duplicate = add(historyItem("pinned"))
    XCTAssertTrue(duplicate === pinned)
    XCTAssertEqual(history.unpinnedItems, [second, first])
    XCTAssertEqual(history.pinnedItems, [pinned])
    XCTAssertEqual(pinned.item.numberOfCopies, 2)
    XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()), 3)
    XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>()), 3)
  }

  func testAddingCopyPreservesActiveSearch() async throws {
    add(historyItem("match"))
    history.searchQuery = "match"
    add(historyItem("unrelated"))
    XCTAssertEqual(history.items.map(\.title), ["match"])
    XCTAssertEqual(history.searchQuery, "match")
    history.searchQuery = ""
  }

  func testInvalidHistorySizeDoesNotCrash() {
    Defaults[.size] = -1
    add(historyItem("first"))
    add(historyItem("second"))
    XCTAssertEqual(history.items.map(\.title), ["second"])
  }

  func testNewCopyIsRetainedWhenSortingByFrequency() {
    Defaults[.size] = 1
    Defaults[.sortBy] = .numberOfCopies
    add(historyItem("frequent"))
    add(historyItem("frequent"))
    add(historyItem("new"))
    XCTAssertEqual(history.items.map(\.title), ["new"])
  }

  func testClearingAllRemovesPinnedContentFromStorage() throws {
    let pinned = add(historyItem("pinned"))
    pinned.togglePin()
    add(historyItem("plain"))
    XCTAssertTrue(history.clearAll())
    XCTAssertTrue(history.all.isEmpty)
    XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()), 0)
    XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>()), 0)
  }

  func testFailedStorageOperationsPreserveHistory() async throws {
    let container = try ModelContainer(
      for: HistoryItem.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let model = HistoryItem(contents: [HistoryItemContent(type: "public.utf8-plain-text", value: Data("saved".utf8))])
    model.title = "saved"
    context.insert(model)
    try context.save()
    let failingHistory = History(context: context, observeDefaults: false, saveChanges: { _ in
      throw CocoaError(.fileWriteOutOfSpace)
    })
    try await failingHistory.load()
    let original = try XCTUnwrap(failingHistory.items.first)

    XCTAssertFalse(failingHistory.delete(original))
    XCTAssertEqual(failingHistory.items, [original])
    XCTAssertFalse(failingHistory.clearAll())
    XCTAssertEqual(failingHistory.items, [original])
    let incoming = HistoryItem(contents: [HistoryItemContent(type: "public.utf8-plain-text", value: Data("new".utf8))])
    XCTAssertNil(failingHistory.add(incoming))
    XCTAssertEqual(failingHistory.items, [original])
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryItem>()), 1)
    XCTAssertNotNil(failingHistory.storageError)
  }

  func testImageIntentExportsDistinctPNGFiles() async throws {
    let contents = HistoryItemContent(
      type: NSPasteboard.PasteboardType.tiff.rawValue,
      value: NSImage(named: "NSApplicationIcon")!.tiffRepresentation
    )
    let item = HistoryItem(contents: [contents])
    let added = try XCTUnwrap(history.add(item))
    AppState.shared.navigator.select(item: added)
    let get = Get()
    get.selected = true
    let firstResult = try await get.perform()
    let secondResult = try await get.perform()
    let first = try XCTUnwrap(firstResult.value?.image)
    let second = try XCTUnwrap(secondResult.value?.image)
    defer {
      try? FileManager.default.removeItem(at: first)
      try? FileManager.default.removeItem(at: second)
    }
    XCTAssertNotEqual(first, second)
    XCTAssertEqual(try Data(contentsOf: first).prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
    XCTAssertEqual(try Data(contentsOf: second).prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
  }

  func testIntentsRejectInvalidPositions() async {
    await assertInvalidIntentPosition(1)
    add(historyItem("saved"))
    for number in [Int.min, -1, 0, 2, Int.max] {
      await assertInvalidIntentPosition(number)
    }
  }

  private func assertInvalidIntentPosition(_ number: Int) async {
    let get = Get()
    get.selected = false
    get.number = number
    let select = Select()
    select.number = number
    let delete = Delete()
    delete.number = number
    let actions: [() async throws -> Void] = [
      { _ = try await get.perform() },
      { _ = try await select.perform() },
      { _ = try await delete.perform() }
    ]
    for action in actions {
      do {
        try await action()
        XCTFail("Expected notFound for position \(number)")
      } catch AppIntentError.notFound {
        // Expected: invalid input is reported without indexing the array.
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }
  }

  @discardableResult
  private func add(_ item: HistoryItem) -> HistoryItemDecorator {
    guard let added = history.add(item) else {
      XCTFail("Could not add fixture to history")
      return HistoryItemDecorator(item)
    }
    return added
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.numberOfCopies = 1
    item.title = item.generateTitle()

    return item
  }
}
