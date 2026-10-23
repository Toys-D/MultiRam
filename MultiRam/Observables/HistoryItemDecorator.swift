import AppKit.NSWorkspace
import Defaults
import Foundation
import Observation
import Sauce

@Observable
class HistoryItemDecorator: Identifiable, Hashable, HasVisibility {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  static var thumbnailImageSize: NSSize { NSSize(width: 340, height: Defaults[.imageMaxHeight]) }
  // The side panel shows the image at up to this size; the view scales it down to the panel.
  static let expandedImageSize = NSSize(width: 1_600, height: 1_200)
  // Rows show at most four lines, so longer or multi-line text has more to reveal.
  static let expandableTextLength = 200

  let id = UUID()

  var title: String = ""
  var attributedTitle: AttributedString?

  var isVisible: Bool = true
  var selectionIndex: Int = -1
  var isSelected: Bool {
    return selectionIndex != -1
  }
  var shortcuts: [KeyShortcut] {
    guard let pin = item.pin, HistoryItem.supportedPins.contains(pin) else { return [] }
    return KeyShortcut.create(character: pin)
  }

  var thumbnailImageGenerationTask: Task<(), Error>?
  var thumbnailImage: NSImage?
  var expandedImageGenerationTask: Task<(), Error>?
  var expandedImage: NSImage?
  // Text shown in the side panel, captured while the model is still alive.
  private(set) var expandedText = ""
  // Cached so view bodies never touch the model, which may already be deleted from the store.
  private(set) var hasImage = false
  private(set) var hasExpandableContent = false
  @ObservationIgnored private var imageSizeCache: NSSize?
  @ObservationIgnored private var imageSizeResolved = false
  var applicationImage: ApplicationImage

  // 10k characters seems to be more than enough on large displays
  var text: String { item.previewableText.shortened(to: 10_000) }

  // Dimensions of the stored image, read once; decoding the header is enough for this.
  var imageSize: NSSize? {
    if !imageSizeResolved, !item.isDeleted {
      imageSizeCache = item.image?.size
      imageSizeResolved = true
    }
    return imageSizeCache
  }
  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  private(set) var item: HistoryItem

  init(_ item: HistoryItem) {
    self.item = item
    self.title = item.title
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)

    refreshContentFlags()
    synchronizeItemTitle()
  }

  // Recomputed when the model changes; skipped once the model is gone.
  func refreshContentFlags() {
    guard !item.isDeleted else { return }
    hasImage = item.imageData != nil
    let text = self.text
    hasExpandableContent = hasImage || text.contains(where: \.isNewline) || text.count > Self.expandableTextLength
  }

  @MainActor
  func ensureThumbnailImage() {
    guard item.image != nil else {
      return
    }
    guard thumbnailImage == nil else {
      return
    }
    guard thumbnailImageGenerationTask == nil else {
      return
    }
    thumbnailImageGenerationTask = Task { [weak self] in
      guard !Task.isCancelled else { return }
      self?.generateThumbnailImage()
      self?.thumbnailImageGenerationTask = nil
    }
  }

  @MainActor
  func refreshImages() {
    let hadThumbnail = thumbnailImage != nil || thumbnailImageGenerationTask != nil
    cleanupImages()
    if hadThumbnail { ensureThumbnailImage() }
  }

  @MainActor
  func cleanupImages() {
    thumbnailImageGenerationTask?.cancel()
    thumbnailImageGenerationTask = nil
    thumbnailImage?.recache()
    thumbnailImage = nil
    imageSizeResolved = false
    releaseExpandedImage()
  }

  @MainActor
  func ensureExpandedContent() {
    if expandedText.isEmpty, !item.isDeleted {
      expandedText = text
    }
    ensureExpandedImage()
  }

  @MainActor
  func releaseExpandedContent() {
    expandedText = ""
    releaseExpandedImage()
  }

  @MainActor
  func ensureExpandedImage() {
    guard hasImage, expandedImage == nil, expandedImageGenerationTask == nil else {
      return
    }
    expandedImageGenerationTask = Task { [weak self] in
      guard !Task.isCancelled else { return }
      self?.generateExpandedImage()
      self?.expandedImageGenerationTask = nil
    }
  }

  @MainActor
  func releaseExpandedImage() {
    expandedImageGenerationTask?.cancel()
    expandedImageGenerationTask = nil
    expandedImage?.recache()
    expandedImage = nil
  }

  @MainActor
  private func generateExpandedImage() {
    guard !item.isDeleted, let image = item.image else {
      return
    }
    expandedImage = image.resized(to: Self.expandedImageSize)
  }

  @MainActor
  private func generateThumbnailImage() {
    guard !item.isDeleted, let image = item.image else {
      return
    }
    thumbnailImage = image.resized(to: HistoryItemDecorator.thumbnailImageSize)
  }

  func highlight(_ query: String, _ ranges: [Range<String.Index>]) {
    guard !query.isEmpty, !title.isEmpty else {
      attributedTitle = nil
      return
    }

    var attributedString = AttributedString(title.shortened(to: 500))
    for range in ranges {
      if let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
         let upperBound = AttributedString.Index(range.upperBound, within: attributedString) {
        switch Defaults[.highlightMatch] {
        case .bold:
          attributedString[lowerBound..<upperBound].font = .bold(.body)()
        case .italic:
          attributedString[lowerBound..<upperBound].font = .italic(.body)()
        case .underline:
          attributedString[lowerBound..<upperBound].underlineStyle = .single
        default:
          attributedString[lowerBound..<upperBound].backgroundColor = .findHighlightColor
          attributedString[lowerBound..<upperBound].foregroundColor = .black
        }
      }
    }

    attributedTitle = attributedString
  }

  @MainActor
  func togglePin() {
    if item.pin != nil {
      item.pin = nil
    } else {
      let pin = HistoryItem.randomAvailablePin
      item.pin = pin
    }
  }

  private func synchronizeItemTitle() {
    _ = withObservationTracking {
      item.title
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, !self.item.isDeleted else { return }
        self.title = self.item.title
        self.refreshContentFlags()
        self.synchronizeItemTitle()
      }
    }
  }
}
