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

  private func keys(in table: String, language: String, bundle: Bundle) throws -> Set<String> {
    let url = try XCTUnwrap(
      bundle.url(forResource: table, withExtension: "strings", subdirectory: nil, localization: language),
      "\(language).lproj/\(table).strings"
    )
    let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    return Set(strings.keys)
  }
}
