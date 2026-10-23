import SwiftUI

// Full content of a history item, shown in the side panel next to the list.
struct HistoryItemDetailView: View {
  @Bindable var item: HistoryItemDecorator

  var body: some View {
    Group {
      if item.hasImage {
        VStack(spacing: 0) {
          imageContent
            .padding(Popup.detailPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          Divider()
          OpenWithBar(item: item)
        }
      } else {
        ScrollView {
          Text(verbatim: item.expandedText)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("history-item-detail")
        }
        .padding(Popup.detailPadding)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      item.ensureExpandedContent()
    }
  }

  @ViewBuilder
  private var imageContent: some View {
    if let image = item.expandedImage {
      Image(nsImage: image)
        .resizable()
        .scaledToFit()
        // Never upscale: the stored image is already capped at expandedImageSize.
        .frame(maxWidth: image.size.width, maxHeight: image.size.height)
        .accessibilityIdentifier("history-item-detail")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
