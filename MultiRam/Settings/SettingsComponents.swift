import SwiftUI

enum SettingsTheme {
  // Teal of the front card in the MultiRam logo.
  static let accent = Color(red: 0x14 / 255, green: 0xB8 / 255, blue: 0xD1 / 255)
  static let selectedText = Color.black.opacity(0.85)
}

// Settings strings were written for label-and-colon layouts ("Size:"); grouped forms show them without the colon.
func settingsLabel(_ key: String, table: String) -> String {
  settingsLabel(NSLocalizedString(key, tableName: table, comment: ""))
}

func settingsLabel(_ text: String) -> String {
  // Some strings end with an SF Symbols glyph from the private use area, drawn as "?" outside the old panes.
  let scalars = text.unicodeScalars.filter { $0.properties.generalCategory != .privateUse }
  var label = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
  while let last = label.last, last == ":" || last == "：" {
    label.removeLast()
  }
  return label.trimmingCharacters(in: .whitespaces)
}

// A page title above a grouped form or a custom panel.
struct SettingsPage<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.system(size: 22, weight: .bold))
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 4)
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// A rounded panel for content that does not fit a form row, like tables and lists.
struct SettingsPanel<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
  }
}

extension View {
  func settingsFootnote() -> some View {
    font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
