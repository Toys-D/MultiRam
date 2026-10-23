import Foundation

extension NSRect {
  func constrained(to bounds: NSRect) -> NSRect {
    let size = NSSize(width: min(width, bounds.width), height: min(height, bounds.height))
    return NSRect(
      x: min(max(minX, bounds.minX), bounds.maxX - size.width),
      y: min(max(minY, bounds.minY), bounds.maxY - size.height),
      width: size.width,
      height: size.height
    )
  }

  static func centered(ofSize size: NSSize, in frame: NSRect) -> NSRect {
    let bottomLeftX = (frame.width - size.width) / 2 + frame.minX
    let bottomLeftY = (frame.height - size.height) / 2 + frame.minY

    return NSRect(x: bottomLeftX + 1.0, y: bottomLeftY + 1.0, width: size.width, height: size.height)
  }
}
