import AppKit
import Defaults
import SwiftUI

// The tint of pinned rows is stored as an sRGB hex string like "#14B8D1".
enum PinnedHighlight {
  // Light enough that the title keeps its contrast in both appearances.
  static let opacity = 0.2

  static func color(hex: String) -> NSColor? {
    var digits = hex.trimmingCharacters(in: .whitespaces)
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
    return NSColor(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }

  static func hex(of color: NSColor) -> String {
    let rgb = color.usingColorSpace(.sRGB) ?? color
    func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
    return String(
      format: "#%02X%02X%02X",
      channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent)
    )
  }
}

enum SelectionAppearance {
  case none
  case topConnection
  case bottomConnection
  case topBottomConnection

  func rect(cornerRadius: CGFloat) -> some Shape {
    var cornerRadii = RectangleCornerRadii()
    switch self {
    case .none:
      cornerRadii.topLeading = cornerRadius
      cornerRadii.topTrailing = cornerRadius
      cornerRadii.bottomLeading = cornerRadius
      cornerRadii.bottomTrailing = cornerRadius
    case .topConnection:
      cornerRadii.bottomLeading = cornerRadius
      cornerRadii.bottomTrailing = cornerRadius
    case .bottomConnection:
      cornerRadii.topLeading = cornerRadius
      cornerRadii.topTrailing = cornerRadius
    case .topBottomConnection:
      break
    }
    return .rect(cornerRadii: cornerRadii)
  }
}

struct ListItemView<Title: View, ID: Hashable>: View {
  var id: ID
  var selectionId: UUID
  var appIcon: ApplicationImage?
  var image: NSImage?
  var accessoryImage: NSImage?
  var attributedTitle: AttributedString?
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var selectionIndex: Int?
  var help: LocalizedStringKey?
  var selectionAppearance: SelectionAppearance = .none
  var isPinned: Bool = false
  var onTogglePin: (() -> Void)?
  var canExpand: Bool = false
  var isExpanded: Bool = false
  var onToggleExpand: (() -> Void)?
  var onSelect: (() -> Void)?
  @ViewBuilder var title: () -> Title

  @Default(.showApplicationIcons) private var showIcons
  @Default(.highlightPinned) private var highlightPinned
  @Default(.pinnedHighlightColor) private var pinnedHighlightColor
  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags

  var body: some View {
    HStack(spacing: 0) {
      if let onSelect {
        rowContent
          .contentShape(Rectangle())
          .onTapGesture(perform: onSelect)
      } else {
        rowContent
      }

      if let onTogglePin {
        ToolbarButton(action: onTogglePin) {
          Image(systemName: isPinned ? "pin.fill" : "pin")
            .frame(width: 24, height: Popup.itemHeight)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("pin-history-item")
        .accessibilityLabel(Text(isPinned ? "unpin_item" : "pin_item"))
        .help(Text(isPinned ? "unpin_item" : "pin_item"))
        .padding(.trailing, onToggleExpand == nil ? 8 : 0)
      }

      if let onToggleExpand {
        expandControl(onToggleExpand)
          .padding(.trailing, 8)
      }
    }
    .frame(minHeight: Popup.itemHeight)
    .id(id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(isSelected ? Color.white : .primary)
    // macOS 26 broke hovering if no background is present.
    // The slight opacity white background is a workaround.
    .background(rowBackground)
    .clipShape(selectionAppearance.rect(cornerRadius: Popup.cornerRadius))
    .hoverSelectionId(selectionId)
    .help(help ?? "")
  }

  private var rowBackground: Color {
    if isSelected {
      return Color.accentColor.opacity(0.8)
    }
    if isPinned, highlightPinned, let tint = PinnedHighlight.color(hex: pinnedHighlightColor) {
      return Color(nsColor: tint).opacity(PinnedHighlight.opacity)
    }
    return .white.opacity(0.001)
  }

  // Rows without extra content keep an empty slot so the pin column stays aligned.
  @ViewBuilder
  private func expandControl(_ onToggleExpand: @escaping () -> Void) -> some View {
    if canExpand {
      ToolbarButton(action: onToggleExpand) {
        Image(systemName: isExpanded ? "chevron.left" : "chevron.right")
          .frame(width: 24, height: Popup.itemHeight)
          .contentShape(Rectangle())
      }
      .accessibilityIdentifier("expand-history-item")
      .accessibilityLabel(Text(isExpanded ? "collapse_item" : "expand_item"))
      .help(Text(isExpanded ? "collapse_item" : "expand_item"))
    } else {
      Color.clear
        .frame(width: 24, height: Popup.itemHeight)
        .accessibilityHidden(true)
    }
  }

  private var rowContent: some View {
    HStack(spacing: 0) {
      if showIcons, let appIcon {
        VStack {
          Spacer(minLength: 0)
          AppImageView(appImage: appIcon, size: NSSize(width: 15, height: 15))
          Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.vertical, 5)
      }

      Spacer()
        .frame(width: showIcons ? 5 : 10)

      if let accessoryImage {
        Image(nsImage: accessoryImage)
          .accessibilityIdentifier("copy-history-item")
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      }

      if let image {
        Image(nsImage: image)
          .accessibilityIdentifier("copy-history-item")
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      } else {
        ListItemTitleView(attributedTitle: attributedTitle, title: title)
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      }

      Spacer()

      HStack(spacing: 5) {
        if let index = selectionIndex {
          Text("\(index + 1)")
            .font(.caption)
            .frame(minWidth: 10, alignment: .center)
            .padding(3)
            .background(
              Color.secondary.opacity(isSelected ? 0.5 : 0.8),
              in: Capsule()
            )
            .foregroundStyle(Color.white)
        }

        if !shortcuts.isEmpty {
          ZStack(alignment: .trailing) {
            ForEach(shortcuts) { shortcut in
              let visible = shortcut.isVisible(shortcuts, modifierFlags.flags)
              KeyboardShortcutView(shortcut: shortcut)
                .opacity(visible ? 1 : 0)
                .frame(width: visible ? nil : 0)
            }
          }
        }
      }
      .padding(.trailing, 10)
    }
    .frame(minHeight: Popup.itemHeight)
  }
}
