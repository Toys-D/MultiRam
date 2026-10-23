import Foundation

enum AppIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
  case notFound
  case storageFailure
  case invalidImage

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .notFound: return "Clipboard item not found"
    case .storageFailure: return "Could not update clipboard history"
    case .invalidImage: return "Could not export clipboard image"
    }
  }
}
