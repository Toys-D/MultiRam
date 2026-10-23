import SwiftUI

struct ListItemTitleView<Title: View>: View {
  var attributedTitle: AttributedString?
  @ViewBuilder var title: () -> Title

  var body: some View {
    Group {
      if let attributedTitle {
        Text(attributedTitle)
      } else {
        title()
          // Workaround for macOS 26 to avoid flipped text
          // https://github.com/p0deje/Maccy/issues/1113
          .drawingGroup()
      }
    }
    .accessibilityIdentifier("copy-history-item")
    .lineLimit(4)
    .truncationMode(.tail)
    .multilineTextAlignment(.leading)
    .fixedSize(horizontal: false, vertical: true)
  }
}
