import Foundation
import AppIntents
import AppKit

struct Get: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "GetIntent"

  static var title: LocalizedStringResource = "Get Item from Clipboard History"
  static var description = IntentDescription("""
  Gets an item from MultiRam clipboard history.
  The returned item can be used to access its plain/rich/HTML text, image contents or file location.
  """)

  @Parameter(title: "Selected", default: true)
  var selected: Bool

  @Parameter(title: "Number", default: 1)
  var number: Int

  private let positionOffset = 1

  static var parameterSummary: some ParameterSummary {
    When(\.$selected, .equalTo, false) {
      Summary {
        \.$number
        \.$selected
      }
    } otherwise: {
      Summary {
        \.$selected
      }
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<HistoryItemAppEntity> {
    var item: HistoryItem?
    if selected {
      item = AppState.shared.navigator.selection.first?.item
    } else {
      let items = AppState.shared.history.items
      if number > 0, number <= items.count {
        item = items[number - positionOffset].item
      }
    }

    guard let item else {
      throw AppIntentError.notFound
    }

    let intentItem = HistoryItemAppEntity()
    intentItem.text = item.text

    if let html = item.htmlData {
      intentItem.html = String(data: html, encoding: .utf8)
    }

    if let fileURL = item.fileURLs.first {
      intentItem.file = fileURL
    }

    if let imageData = item.imageData {
      let directory = URL.temporaryDirectory.appending(path: "MultiRam-Exports", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appending(path: "\(UUID().uuidString).png")
      guard let png = NSBitmapImageRep(data: imageData)?.representation(using: .png, properties: [:]) else {
        throw AppIntentError.invalidImage
      }
      try png.write(to: file, options: [.atomic, .completeFileProtection])
      intentItem.image = file
    }

    if let rtf = item.rtfData {
      intentItem.richText = String(data: rtf, encoding: .utf8)
    }

    return .result(value: intentItem)
  }
}
