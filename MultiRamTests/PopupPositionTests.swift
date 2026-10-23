import AppKit
import Defaults
import SwiftUI
import XCTest
@testable import MultiRam

class PopupPositionTests: XCTestCase {
  private let visibleFrame = NSRect(x: 0, y: 70, width: 1440, height: 805)

  func testCollapsedHeightLimitIsRecovered() {
    for height: CGFloat in [0, 39, 108, .infinity, .nan] {
      XCTAssertEqual(Popup.maximumHeight(for: height), Defaults.Keys.windowSize.defaultValue.height)
    }
  }

  func testUsableHeightLimitIsPreserved() {
    for height: CGFloat in [150, 300, 600, 800] {
      XCTAssertEqual(Popup.maximumHeight(for: height), height)
    }
  }

  @MainActor
  func testAutomaticResizingPreservesRecoveredHeightLimit() async throws {
    let savedSize = Defaults[.windowSize]
    defer { Defaults[.windowSize] = savedSize }
    let panel = FloatingPanel(
      contentRect: NSRect(x: 0, y: 0, width: 450, height: 39),
      onClose: {}
    ) { Text("Height regression fixture") }
    let recoveredHeight = Defaults.Keys.windowSize.defaultValue.height
    XCTAssertEqual(Defaults[.windowSize].height, recoveredHeight)
    XCTAssertEqual(Defaults[.windowSize].width, 450)

    panel.verticallyResize(to: 39)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(Defaults[.windowSize].height, recoveredHeight)
    XCTAssertEqual(AppState.shared.popup.preferredHeight(for: 400), 400)
  }

  func testDetailPanelOpensOnTheTrailingSideWhenThereIsRoom() {
    let layout = DetailPanelLayout.expanded(
      listFrame: NSRect(x: 100, y: 100, width: 450, height: 600), detailWidth: 560, visibleFrame: visibleFrame
    )
    XCTAssertEqual(layout.frame, NSRect(x: 100, y: 100, width: 1010, height: 600))
    XCTAssertEqual(layout.side, .trailing)
    XCTAssertEqual(layout.detailWidth, 560)
  }

  func testDetailPanelOpensOnTheLeadingSideNearTheRightEdge() {
    let layout = DetailPanelLayout.expanded(
      listFrame: NSRect(x: 900, y: 100, width: 450, height: 600), detailWidth: 560, visibleFrame: visibleFrame
    )
    XCTAssertEqual(layout.frame, NSRect(x: 340, y: 100, width: 1010, height: 600))
    XCTAssertEqual(layout.side, .leading)
  }

  func testDetailPanelShiftsTheListWhenNeitherSideFits() {
    let layout = DetailPanelLayout.expanded(
      listFrame: NSRect(x: 600, y: 100, width: 450, height: 600), detailWidth: 900, visibleFrame: visibleFrame
    )
    XCTAssertEqual(layout.frame, NSRect(x: 90, y: 100, width: 1350, height: 600))
    XCTAssertEqual(layout.side, .trailing)
    XCTAssertTrue(visibleFrame.contains(layout.frame))
  }

  func testDetailPanelWidthIsClampedToTheScreen() {
    let layout = DetailPanelLayout.expanded(
      listFrame: NSRect(x: 0, y: 100, width: 450, height: 600), detailWidth: 1200, visibleFrame: visibleFrame
    )
    XCTAssertEqual(layout.detailWidth, 990)
    XCTAssertEqual(layout.frame.width, 1440)
  }

  func testCollapsedFrameRestoresTheListOnEitherSide() {
    let leading = DetailPanelLayout.collapsed(
      frame: NSRect(x: 340, y: 100, width: 1010, height: 600), side: .leading, detailWidth: 560
    )
    XCTAssertEqual(leading, NSRect(x: 900, y: 100, width: 450, height: 600))
    let trailing = DetailPanelLayout.collapsed(
      frame: NSRect(x: 100, y: 100, width: 1010, height: 600), side: .trailing, detailWidth: 560
    )
    XCTAssertEqual(trailing, NSRect(x: 100, y: 100, width: 450, height: 600))
  }

  func testTextDetailUsesFixedWidthWithinHalfTheScreen() {
    XCTAssertEqual(Popup.detailWidth(imageSize: nil, panelHeight: 800, screenWidth: 1440), Popup.textDetailWidth)
    XCTAssertEqual(Popup.detailWidth(imageSize: nil, panelHeight: 800, screenWidth: 1000), 500)
  }

  func testImageDetailWidthFollowsAspectRatioWithoutUpscaling() {
    let padding = Popup.detailPadding * 2
    // A wide image is scaled to the panel height, then capped at half the screen.
    XCTAssertEqual(
      Popup.detailWidth(imageSize: NSSize(width: 1600, height: 800), panelHeight: 800, screenWidth: 1440), 720
    )
    // A small image keeps its natural size and only adds padding.
    XCTAssertEqual(
      Popup.detailWidth(imageSize: NSSize(width: 400, height: 150), panelHeight: 800, screenWidth: 1440),
      400 + padding
    )
    XCTAssertEqual(
      Popup.detailWidth(imageSize: NSSize(width: 100, height: 100), panelHeight: 800, screenWidth: 1440),
      Popup.minimumDetailWidth
    )
  }

  func testImageDetailWidthLeavesRoomForTheActionBar() {
    let padding = Popup.detailPadding * 2
    let available = 600 - padding - Popup.detailActionBarHeight
    XCTAssertEqual(
      Popup.detailWidth(imageSize: NSSize(width: 1000, height: 1000), panelHeight: 600, screenWidth: 4000),
      available.rounded() + padding
    )
  }

  func testDetailPreferredHeightFitsContentWithinTheLimit() {
    let padding = Popup.detailPadding * 2
    XCTAssertEqual(Popup.detailPreferredHeight(imageSize: NSSize(width: 480, height: 200), text: "", limit: 800),
                   200 + padding + Popup.detailActionBarHeight)
    XCTAssertEqual(Popup.detailPreferredHeight(imageSize: NSSize(width: 2000, height: 2000), text: "", limit: 800),
                   800)
    let oneLine = Popup.detailPreferredHeight(imageSize: nil, text: "short", limit: 800)
    XCTAssertGreaterThan(oneLine, padding)
    XCTAssertLessThan(oneLine, 100)
    let manyLines = Array(repeating: "line", count: 200).joined(separator: "\n")
    XCTAssertEqual(Popup.detailPreferredHeight(imageSize: nil, text: manyLines, limit: 800), 800)
  }

  @MainActor
  func testToggleDetailShowsAnItemThenHidesIt() {
    let popup = AppState.shared.popup
    defer { popup.closeDetail() }
    let item = HistoryItemDecorator(HistoryItem())
    popup.toggleDetail(for: item)
    XCTAssertTrue(popup.detailItem === item)
    XCTAssertGreaterThanOrEqual(popup.detailWidth, Popup.minimumDetailWidth)
    popup.toggleDetail(for: item)
    XCTAssertNil(popup.detailItem)
    XCTAssertEqual(popup.detailWidth, 0)
  }

  @MainActor
  func testToggleDetailSwitchesBetweenItems() {
    let popup = AppState.shared.popup
    defer { popup.closeDetail() }
    let first = HistoryItemDecorator(HistoryItem())
    let second = HistoryItemDecorator(HistoryItem())
    popup.toggleDetail(for: first)
    popup.toggleDetail(for: second)
    XCTAssertTrue(popup.detailItem === second)
  }

  @MainActor
  func testResetClosesDetail() {
    let popup = AppState.shared.popup
    popup.toggleDetail(for: HistoryItemDecorator(HistoryItem()))
    popup.reset()
    XCTAssertNil(popup.detailItem)
  }

  func testEventsMonitorCanBeReinstalledAfterRemoval() {
    let popup = AppState.shared.popup
    defer { popup.initEventsMonitor() }
    popup.deinitEventsMonitor()
    XCTAssertFalse(popup.hasEventsMonitor)
    popup.initEventsMonitor()
    XCTAssertTrue(popup.hasEventsMonitor)
  }

  func testOpensBelowCursorWhenThereIsRoom() {
    let cursor = NSPoint(x: 200, y: 800)
    let frame = PopupPosition.frameAtCursor(
      size: NSSize(width: 450, height: 400), cursor: cursor, visibleFrame: visibleFrame
    )
    XCTAssertEqual(frame.maxY, cursor.y)
    XCTAssertEqual(frame.minX, cursor.x)
    XCTAssertTrue(visibleFrame.contains(frame))
  }

  func testOpensAboveCursorNearBottom() {
    let cursor = NSPoint(x: 200, y: 90)
    let frame = PopupPosition.frameAtCursor(
      size: NSSize(width: 450, height: 600), cursor: cursor, visibleFrame: visibleFrame
    )
    XCTAssertEqual(frame.minY, cursor.y)
    XCTAssertEqual(frame.height, 600)
    XCTAssertTrue(visibleFrame.contains(frame))
  }

  func testImageLoadingCanFlipWindowUpwards() {
    let cursor = NSPoint(x: 200, y: 150)
    let initial = PopupPosition.frameAtCursor(
      size: NSSize(width: 450, height: 50), cursor: cursor, visibleFrame: visibleFrame
    )
    let loaded = PopupPosition.frameAtCursor(
      size: NSSize(width: 450, height: 600), cursor: cursor, visibleFrame: visibleFrame
    )
    XCTAssertEqual(initial.maxY, cursor.y)
    XCTAssertEqual(loaded.minY, cursor.y)
    XCTAssertTrue(visibleFrame.contains(loaded))
  }

  func testRightEdgeAndPreviewRemainOnScreen() {
    let cursor = NSPoint(x: 1420, y: 90)
    let frame = PopupPosition.frameAtCursor(
      size: NSSize(width: 850, height: 600), cursor: cursor, visibleFrame: visibleFrame
    )
    XCTAssertEqual(frame.maxX, visibleFrame.maxX)
    XCTAssertEqual(frame.minY, cursor.y)
    XCTAssertTrue(visibleFrame.contains(frame))
  }

  func testVeryTallHistoryFitsTheVisibleScreen() {
    let frame = PopupPosition.frameAtCursor(
      size: NSSize(width: 450, height: 2000),
      cursor: NSPoint(x: 200, y: 90), visibleFrame: visibleFrame
    )
    XCTAssertEqual(frame.height, visibleFrame.height)
    XCTAssertEqual(frame.minY, visibleFrame.minY)
    XCTAssertTrue(visibleFrame.contains(frame))
  }

  func testCursorOverDockStillKeepsWindowVisible() {
    let frame = PopupPosition.frameAtCursor(
      size: NSSize(width: 450, height: 600),
      cursor: NSPoint(x: 200, y: 10), visibleFrame: visibleFrame
    )
    XCTAssertEqual(frame.minY, visibleFrame.minY)
    XCTAssertTrue(visibleFrame.contains(frame))
  }

  func testSecondaryScreenWithNegativeCoordinates() {
    let screen = NSRect(x: -1920, y: -1000, width: 1920, height: 960)
    let cursor = NSPoint(x: -30, y: -980)
    let frame = PopupPosition.frameAtCursor(
      size: NSSize(width: 850, height: 700), cursor: cursor, visibleFrame: screen
    )
    XCTAssertEqual(frame.maxX, screen.maxX)
    XCTAssertEqual(frame.minY, cursor.y)
    XCTAssertTrue(screen.contains(frame))
  }

  func testResizeWithoutCursorAnchorIsClampedAtAllEdges() {
    for origin in [NSPoint(x: -500, y: -500), NSPoint(x: 1500, y: 900)] {
      let proposed = NSRect(origin: origin, size: NSSize(width: 850, height: 600))
      XCTAssertTrue(visibleFrame.contains(proposed.constrained(to: visibleFrame)))
    }
  }
}
