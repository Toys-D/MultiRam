import Foundation

// The interface language. "System" leaves the choice to macOS: the first language from the
// system list that MultiRam has, or English, the development language, when it has none of them.
enum AppLanguage {
  static let system = "system"
  static let preferenceKey = "AppleLanguages"

  // Each language named in itself, so anyone can find their own.
  static let choices: [(code: String, name: String)] = [
    ("en", "English"),
    ("es", "Español"),
    ("fr", "Français"),
    ("de", "Deutsch"),
    ("pt-BR", "Português (Brasil)"),
    ("zh-Hans", "简体中文"),
    ("zh-Hant", "繁體中文"),
    ("ru", "Русский"),
    ("uk", "Українська")
  ]

  // Only the app's own domain counts: the global AppleLanguages is the system list, not a choice.
  static func selected(in defaults: UserDefaults, domain: String) -> String {
    let languages = defaults.persistentDomain(forName: domain)?[preferenceKey] as? [String]
    guard let code = languages?.first, choices.contains(where: { $0.code == code }) else { return system }
    return code
  }

  static func select(_ code: String, in defaults: UserDefaults) {
    if code == system {
      defaults.removeObject(forKey: preferenceKey)
    } else {
      defaults.set([code], forKey: preferenceKey)
    }
  }

  // The language the running process uses; a new choice applies after a restart.
  static var current: String {
    Bundle.main.preferredLocalizations.first ?? "en"
  }

  // The language a choice leads to on this Mac, to tell whether a restart would change anything.
  static func resolved(_ code: String, preferred: [String] = Locale.preferredLanguages) -> String {
    guard code == system else { return code }
    return Bundle.preferredLocalizations(from: choices.map(\.code), forPreferences: preferred).first ?? "en"
  }
}
