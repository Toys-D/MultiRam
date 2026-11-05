import XCTest
@testable import MultiRam

final class LocalizationTests: XCTestCase {
  // A missing key shows its raw identifier (for example "pin_item") in that language.
  func testEveryLanguageHasEveryString() throws {
    let bundle = Bundle(for: AppState.self)
    for table in ["Localizable", "GeneralSettings"] {
      let english = try keys(in: table, language: "en", bundle: bundle)
      XCTAssertFalse(english.isEmpty)
      for language in bundle.localizations where language != "Base" && language != "en" {
        let translated = try keys(in: table, language: language, bundle: bundle)
        XCTAssertEqual(english.subtracting(translated).sorted(), [], "\(language).lproj/\(table).strings")
      }
    }
  }

  // A string identical to English is untranslated, except words the language writes the same way.
  func testEveryLanguageTranslatesEveryString() throws {
    let bundle = Bundle(for: AppState.self)
    let sameAsEnglish: Set<String> = [
      "es/AppearanceSettings.HighlightMatchColor", "es/AppearanceSettings.PopupAtCursor", "es/GeneralSettings.Title",
      "pt-BR/AppearanceSettings.PopupAtCursor", "fr/IgnoreSettings.ApplicationsTab", "fr/Localizable.about_contact",
      "fr/Localizable.about_version", "fr/Localizable.filter_images", "fr/StorageSettings.Images",
      "de/Localizable.about_repository", "de/Localizable.filter_text", "de/StorageSettings.Text"
    ]
    for table in ["Localizable", "GeneralSettings", "StorageSettings", "AppearanceSettings", "PinsSettings",
                  "IgnoreSettings", "AdvancedSettings"] {
      let english = try strings(in: table, language: "en", bundle: bundle)
      for language in bundle.localizations where language != "Base" && language != "en" {
        let translated = try strings(in: table, language: language, bundle: bundle)
        let untranslated = english.filter { key, value in
          translated[key] == value && !sameAsEnglish.contains("\(language)/\(table).\(key)")
            && value.rangeOfCharacter(from: .letters) != nil && !value.hasPrefix("defaults write")
        }
        XCTAssertEqual(untranslated.keys.sorted(), [], "\(language).lproj/\(table).strings")
      }
    }
  }

  // A missing or extra placeholder shows "%@" or "{accessibility}" to the user, or drops a value.
  func testEveryLanguageKeepsThePlaceholders() throws {
    let bundle = Bundle(for: AppState.self)
    let placeholder = try NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dfs]|\\{(?:accessibility|pane|settings)\\}")
    func placeholders(_ text: String) -> [String] {
      placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text))
        .map { (text as NSString).substring(with: $0.range).replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }
        .sorted()
    }
    for table in ["Localizable", "GeneralSettings", "StorageSettings", "AppearanceSettings", "PinsSettings",
                  "IgnoreSettings", "AdvancedSettings"] {
      let english = try strings(in: table, language: "en", bundle: bundle)
      for language in bundle.localizations where language != "Base" && language != "en" {
        let translated = try strings(in: table, language: language, bundle: bundle)
        for (key, value) in english {
          XCTAssertEqual(placeholders(translated[key] ?? ""), placeholders(value), "\(language) \(table).\(key)")
        }
      }
    }
  }

  func testShipsOnlyTheSupportedLanguages() {
    let languages = Set(Bundle(for: AppState.self).localizations).subtracting(["Base"])
    XCTAssertEqual(languages, ["en", "es", "fr", "de", "zh-Hans", "zh-Hant", "pt-BR", "ru", "uk"])
  }

  private func strings(in table: String, language: String, bundle: Bundle) throws -> [String: String] {
    let url = try XCTUnwrap(
      bundle.url(forResource: table, withExtension: "strings", subdirectory: nil, localization: language),
      "\(language).lproj/\(table).strings"
    )
    return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
  }

  private func keys(in table: String, language: String, bundle: Bundle) throws -> Set<String> {
    let url = try XCTUnwrap(
      bundle.url(forResource: table, withExtension: "strings", subdirectory: nil, localization: language),
      "\(language).lproj/\(table).strings"
    )
    let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    return Set(strings.keys)
  }
}

final class AppLanguageTests: XCTestCase {
  private let suite = "AppLanguageTests"
  private var defaults: UserDefaults!

  override func setUp() {
    defaults = UserDefaults(suiteName: suite)
    defaults.removePersistentDomain(forName: suite)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
  }

  func testFollowsTheSystemUntilALanguageIsChosen() {
    XCTAssertEqual(AppLanguage.selected(in: defaults, domain: suite), AppLanguage.system)
    AppLanguage.select("de", in: defaults)
    XCTAssertEqual(AppLanguage.selected(in: defaults, domain: suite), "de")
    XCTAssertEqual(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String], ["de"])
    AppLanguage.select(AppLanguage.system, in: defaults)
    XCTAssertEqual(AppLanguage.selected(in: defaults, domain: suite), AppLanguage.system)
    XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
  }

  // A system language MultiRam does not have falls back to English.
  func testUnsupportedSystemLanguageMeansEnglish() {
    XCTAssertEqual(AppLanguage.resolved(AppLanguage.system, preferred: ["ja-JP"]), "en")
    XCTAssertEqual(AppLanguage.resolved(AppLanguage.system, preferred: ["fr-CA"]), "fr")
    XCTAssertEqual(AppLanguage.resolved(AppLanguage.system, preferred: ["pt-BR"]), "pt-BR")
    XCTAssertEqual(AppLanguage.resolved("uk", preferred: ["ja-JP"]), "uk")
  }

  func testEveryChoiceShipsWithTheApp() {
    let shipped = Set(Bundle(for: AppState.self).localizations)
    for choice in AppLanguage.choices {
      XCTAssertTrue(shipped.contains(choice.code), choice.code)
    }
  }
}
