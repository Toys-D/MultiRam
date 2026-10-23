import Foundation

enum DetailPanelSide {
  case trailing
  case leading
}

// Geometry of the popup window while a history item is shown in the side panel.
struct DetailPanelLayout: Equatable {
  let frame: NSRect
  let side: DetailPanelSide
  let detailWidth: CGFloat

  // Widens the list frame on the side that has room, keeping the list in place whenever possible.
  static func expanded(listFrame: NSRect, detailWidth: CGFloat, visibleFrame: NSRect) -> DetailPanelLayout {
    let width = max(0, min(detailWidth, visibleFrame.width - listFrame.width)).rounded()
    var frame = listFrame
    frame.size.width += width
    if listFrame.maxX + width <= visibleFrame.maxX {
      return DetailPanelLayout(frame: frame.constrained(to: visibleFrame), side: .trailing, detailWidth: width)
    }
    if listFrame.minX - width >= visibleFrame.minX {
      frame.origin.x -= width
      return DetailPanelLayout(frame: frame.constrained(to: visibleFrame), side: .leading, detailWidth: width)
    }
    // Neither side fits: keep the panel trailing and let the whole window shift onto the screen.
    return DetailPanelLayout(frame: frame.constrained(to: visibleFrame), side: .trailing, detailWidth: width)
  }

  // Restores the list-only frame after the panel closes.
  static func collapsed(frame: NSRect, side: DetailPanelSide, detailWidth: CGFloat) -> NSRect {
    var listFrame = frame
    listFrame.size.width -= detailWidth
    if side == .leading {
      listFrame.origin.x += detailWidth
    }
    return listFrame
  }
}
