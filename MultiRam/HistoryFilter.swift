import Defaults
import Foundation

enum HistoryItemKind {
  case text, image, file

  // Copied files come first: Finder also puts the file icon on the pasteboard as an image.
  static func of(hasFiles: Bool, hasImage: Bool) -> HistoryItemKind {
    if hasFiles { return .file }
    if hasImage { return .image }
    return .text
  }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
  case all, text, images, files

  var id: String { rawValue }

  var title: String {
    NSLocalizedString("filter_\(rawValue)", comment: "")
  }

  var symbol: String {
    switch self {
    case .all: return "square.stack"
    case .text: return "text.alignleft"
    case .images: return "photo"
    case .files: return "doc"
    }
  }

  func includes(_ kind: HistoryItemKind) -> Bool {
    switch self {
    case .all: return true
    case .text: return kind == .text
    case .images: return kind == .image
    case .files: return kind == .file
    }
  }
}

// How long unpinned items are kept; 0 keeps them until the history size limit removes them.
enum HistoryRetention: Int, CaseIterable, Identifiable {
  case forever = 0
  case day = 1
  case week = 7
  case month = 30
  case quarter = 90
  case year = 365

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .forever: return NSLocalizedString("keep_forever", comment: "")
    case .day: return NSLocalizedString("keep_day", comment: "")
    case .week: return NSLocalizedString("keep_week", comment: "")
    case .month: return NSLocalizedString("keep_month", comment: "")
    case .quarter: return NSLocalizedString("keep_quarter", comment: "")
    case .year: return NSLocalizedString("keep_year", comment: "")
    }
  }

  // Items last copied before this date are expired.
  func cutoff(now: Date) -> Date? {
    guard rawValue > 0 else { return nil }
    return now.addingTimeInterval(-Double(rawValue) * 86_400)
  }
}

extension HistoryRetention: Defaults.Serializable {}
