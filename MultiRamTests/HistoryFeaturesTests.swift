import AppKit
import Defaults
import Sauce
import XCTest
@testable import MultiRam

final class HistoryFilterTests: XCTestCase {
  func testCopiedFilesCountAsFilesEvenWithTheirIcon() {
    XCTAssertEqual(HistoryItemKind.of(hasFiles: true, hasImage: true), .file)
    XCTAssertEqual(HistoryItemKind.of(hasFiles: false, hasImage: true), .image)
    XCTAssertEqual(HistoryItemKind.of(hasFiles: false, hasImage: false), .text)
  }

  func testEachFilterShowsItsKind() {
    XCTAssertTrue(HistoryFilter.all.includes(.file))
    XCTAssertTrue(HistoryFilter.text.includes(.text))
    XCTAssertFalse(HistoryFilter.text.includes(.image))
    XCTAssertTrue(HistoryFilter.images.includes(.image))
    XCTAssertFalse(HistoryFilter.images.includes(.file))
    XCTAssertTrue(HistoryFilter.files.includes(.file))
    for filter in HistoryFilter.allCases {
      XCTAssertFalse(filter.title.hasPrefix("filter_"), filter.rawValue)
    }
  }

  func testRetentionCutoff() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    XCTAssertNil(HistoryRetention.forever.cutoff(now: now))
    XCTAssertEqual(HistoryRetention.week.cutoff(now: now), now.addingTimeInterval(-7 * 86_400))
    for retention in HistoryRetention.allCases {
      XCTAssertFalse(retention.title.hasPrefix("keep_"), "\(retention)")
    }
  }

  func testPinnedHighlightColorSurvivesHex() throws {
    let color = try XCTUnwrap(PinnedHighlight.color(hex: "#14B8D1"))
    XCTAssertEqual(PinnedHighlight.hex(of: color), "#14B8D1")
    XCTAssertNil(PinnedHighlight.color(hex: "nonsense"))
    XCTAssertEqual(Defaults.Keys.pinnedHighlightColor.defaultValue, "#14B8D1")
    XCTAssertTrue(Defaults.Keys.highlightPinned.defaultValue)
  }

  func testSpaceAndCommandYTogglePreview() {
    XCTAssertEqual(KeyChord(.space, []), .togglePreview)
    XCTAssertEqual(KeyChord(.y, [.command]), .togglePreview)
    XCTAssertNotEqual(KeyChord(.space, [.control]), .togglePreview)
  }
}

@MainActor
final class HistoryFeaturesTests: XCTestCase {
  let history = History.shared
  let savedSize = Defaults[.size]

  override func setUp() {
    super.setUp()
    history.clearAll()
    history.filter = .all
    Defaults[.size] = 10
  }

  override func tearDown() {
    history.filter = .all
    Defaults[.size] = savedSize
    super.tearDown()
  }

  func testFilterKeepsOnlyItemsOfThatKind() throws {
    let text = try XCTUnwrap(history.add(item(text: "hello")))
    let image = try XCTUnwrap(history.add(item(image: true)))
    XCTAssertEqual(text.kind, .text)
    XCTAssertEqual(image.kind, .image)

    history.filter = .images
    XCTAssertEqual(history.items, [image])

    history.filter = .text
    XCTAssertEqual(history.items, [text])

    history.filter = .all
    XCTAssertEqual(Set(history.items), [text, image])
  }

  func testExpiredItemsAreRemovedButPinnedOnesStay() throws {
    let now = Date()
    let old = try XCTUnwrap(history.add(item(text: "old", lastCopiedAt: now.addingTimeInterval(-10 * 86_400))))
    let pinned = try XCTUnwrap(history.add(item(text: "pinned", lastCopiedAt: now.addingTimeInterval(-10 * 86_400))))
    history.togglePin(pinned)
    let fresh = try XCTUnwrap(history.add(item(text: "fresh", lastCopiedAt: now)))

    history.removeExpired(retention: .week, now: now)

    XCTAssertFalse(history.items.contains(old))
    XCTAssertTrue(history.items.contains(pinned))
    XCTAssertTrue(history.items.contains(fresh))
  }

  func testKeepingForeverRemovesNothing() throws {
    let old = try XCTUnwrap(history.add(item(text: "old", lastCopiedAt: .distantPast)))
    history.removeExpired(retention: .forever, now: Date())
    XCTAssertTrue(history.items.contains(old))
  }

  func testMergingJoinsTextInSelectionOrderAndSkipsNonText() throws {
    let first = try XCTUnwrap(history.add(item(text: "first")))
    let image = try XCTUnwrap(history.add(item(image: true)))
    let second = try XCTUnwrap(history.add(item(text: "second")))
    XCTAssertEqual(History.mergedText(of: [second, image, first]), "second\nfirst")
    XCTAssertNil(History.mergedText(of: [image]))
  }

  func testSeveralItemsCanBeSelected() {
    XCTAssertTrue(AppState.shared.multiSelectionEnabled)
  }

  private func item(text: String? = nil, image: Bool = false, lastCopiedAt: Date = .now) -> HistoryItem {
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    var contents: [HistoryItemContent] = []
    if let text {
      contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(text.utf8)))
    }
    if image {
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      )!
      contents.append(HistoryItemContent(
        type: NSPasteboard.PasteboardType.png.rawValue, value: rep.representation(using: .png, properties: [:])
      ))
    }
    item.contents = contents
    item.numberOfCopies = 1
    item.lastCopiedAt = lastCopiedAt
    item.title = item.generateTitle()
    return item
  }
}
