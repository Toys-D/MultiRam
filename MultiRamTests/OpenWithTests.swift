import AppKit
import Defaults
import UniformTypeIdentifiers
import XCTest
@testable import MultiRam

final class ImageEditorCatalogTests: XCTestCase {
  private struct FakeProvider: ApplicationProvider {
    var apps: [URL]
    var defaultApp: URL?
    var browsers: [URL] = []
    var metadata: [URL: AppMetadata] = [:]

    func applications(toOpen type: UTType) -> [URL] { apps }
    func defaultApplication(toOpen type: UTType) -> URL? { defaultApp }
    func browserApplications() -> [URL] { browsers }
    func metadata(for appURL: URL) -> AppMetadata? { metadata[appURL] }
    func displayName(for appURL: URL) -> String { appURL.deletingPathExtension().lastPathComponent }
    func applicationExists(at appURL: URL) -> Bool { apps.contains(appURL) }
  }

  private static func app(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }
  private static func editor(_ id: String, category: String? = nil, types: [String] = ["public.png"],
                             rank: String? = nil) -> AppMetadata {
    AppMetadata(
      bundleIdentifier: id, category: category,
      documentTypes: [.init(role: "Editor", rank: rank, contentTypes: types)]
    )
  }

  private let preview = app("/System/Applications/Preview.app")
  private let photoshop = app("/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app")
  private let photoshopCopy = app("/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app/")
  private let skitch = app("/Applications/Skitch.app")
  private let chrome = app("/Applications/Google Chrome.app")
  private let testingChrome = app("/Users/me/Library/Caches/ms-playwright/chromium/Google Chrome for Testing.app")
  private let quickTime = app("/System/Applications/QuickTime Player.app")
  private let libreOffice = app("/Applications/LibreOffice.app")
  private let colorizer = app("/Applications/Folder Colorizer.app")
  private let pixelmator = app("/Applications/Pixelmator Pro.app")
  private let ownApp = app("/Applications/MultiRam.app")
  private let unreadable = app("/Users/me/Applications/Mystery.app")

  private func catalog(recent: [String] = []) -> ImageEditorCatalog {
    var metadata: [URL: AppMetadata] = [
      preview: AppMetadata(
        bundleIdentifier: "com.apple.Preview", category: "public.app-category.productivity",
        documentTypes: [.init(role: "Viewer", contentTypes: ["public.png"])]
      ),
      photoshop: Self.editor("com.adobe.Photoshop"),
      skitch: AppMetadata(
        bundleIdentifier: "com.skitch.skitch", category: "public.app-category.productivity",
        documentTypes: [.init(role: "Editor", rank: "Default", contentTypes: ["public.image"])]
      ),
      chrome: AppMetadata(
        bundleIdentifier: "com.google.Chrome",
        documentTypes: [.init(role: "Viewer", contentTypes: ["public.png"])]
      ),
      testingChrome: Self.editor("com.google.chrome.for.testing"),
      quickTime: Self.editor("com.apple.QuickTimePlayerX", category: "public.app-category.video"),
      libreOffice: Self.editor("org.libreoffice.script", rank: "Alternate"),
      colorizer: Self.editor("com.softorino.foldercolorizer", category: "public.app-category.utilities"),
      pixelmator: AppMetadata(bundleIdentifier: "com.pixelmatorteam.pixelmator.x",
                              category: "public.app-category.graphics-design"),
      ownApp: Self.editor("local.multiram.MultiRam")
    ]
    metadata[photoshopCopy] = metadata[photoshop]
    let provider = FakeProvider(
      apps: [quickTime, colorizer, photoshop, photoshopCopy, libreOffice, chrome, testingChrome,
             skitch, pixelmator, ownApp, unreadable, preview],
      defaultApp: preview,
      browsers: [chrome, testingChrome],
      metadata: metadata
    )
    return ImageEditorCatalog(provider: provider, ownBundleIdentifier: "local.multiram.MultiRam",
                              recentPaths: { recent })
  }

  func testKeepsImageEditorsAndDropsBrowsersPlayersAndUtilities() {
    let names = catalog().applications(for: .png).featured.map(\.name)
    XCTAssertEqual(names, ["Preview", "Pixelmator Pro", "Adobe Photoshop 2025", "Skitch"])
  }

  func testDefaultApplicationComesFirstEvenWhenItIsOnlyAViewer() {
    XCTAssertEqual(catalog().applications(for: .png).featured.first?.url, preview)
  }

  func testRecentlyUsedApplicationsFollowTheDefault() {
    let names = catalog(recent: [skitch.path]).applications(for: .png).featured.map(\.name)
    XCTAssertEqual(names, ["Preview", "Skitch", "Pixelmator Pro", "Adobe Photoshop 2025"])
  }

  func testFullListSkipsThrowawayCopiesDuplicatesAndItself() {
    let all = catalog().applications(for: .png).all.map(\.name)
    XCTAssertEqual(all.filter { $0 == "Adobe Photoshop 2025" }.count, 1)
    XCTAssertFalse(all.contains("Google Chrome for Testing"))
    XCTAssertFalse(all.contains("MultiRam"))
    XCTAssertTrue(all.contains("Google Chrome"))
    XCTAssertTrue(all.contains("Mystery"))
    XCTAssertEqual(all.first, "Preview")
  }

  func testRecentlyUsedApplicationOutsideTheFilterIsOffered() {
    let names = catalog(recent: [unreadable.path]).applications(for: .png).featured.map(\.name)
    XCTAssertEqual(names, ["Preview", "Mystery", "Pixelmator Pro", "Adobe Photoshop 2025", "Skitch"])
  }

  func testMissingRecentApplicationIsSkipped() {
    let names = catalog(recent: ["/Applications/Gone.app", ownApp.path]).applications(for: .png).featured.map(\.name)
    XCTAssertEqual(names, ["Preview", "Pixelmator Pro", "Adobe Photoshop 2025", "Skitch"])
  }

  func testParsesDocumentTypesFromInfoPlist() {
    let metadata = AppMetadata(infoDictionary: [
      "CFBundleIdentifier": "com.example.Editor",
      "LSApplicationCategoryType": "public.app-category.photography",
      "LSUIElement": true,
      "CFBundleDocumentTypes": [
        ["CFBundleTypeRole": "Editor", "LSHandlerRank": "Owner", "LSItemContentTypes": ["public.jpeg"]],
        ["CFBundleTypeRole": "Viewer", "CFBundleTypeExtensions": ["tif", "tiff"]]
      ]
    ])
    XCTAssertEqual(metadata.bundleIdentifier, "com.example.Editor")
    XCTAssertEqual(metadata.category, "public.app-category.photography")
    XCTAssertTrue(metadata.isAgent)
    XCTAssertEqual(metadata.documentTypes, [
      .init(role: "Editor", rank: "Owner", contentTypes: ["public.jpeg"]),
      .init(role: "Viewer", extensions: ["tif", "tiff"])
    ])
  }

  func testEditorRoleCountsForMatchingExtensionsButNotForWildcards() {
    XCTAssertTrue(ImageEditorCatalog.claimsImageEditing(AppMetadata(
      documentTypes: [.init(role: "Editor", extensions: ["JPG"])]
    )))
    XCTAssertFalse(ImageEditorCatalog.claimsImageEditing(AppMetadata(
      documentTypes: [.init(role: "Editor", contentTypes: ["public.data"], extensions: ["*"])]
    )))
  }
}

@MainActor
final class OpenWithControllerTests: XCTestCase {
  private var directory: URL!
  private let savedRecents = Defaults[.openWithRecentApps]
  private let preview = OpenWithApplication(
    url: URL(fileURLWithPath: "/System/Applications/Preview.app", isDirectory: true),
    name: "Preview", bundleIdentifier: "com.apple.Preview"
  )

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenWithControllerTests-\(UUID().uuidString)", isDirectory: true)
    Defaults[.openWithRecentApps] = []
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    Defaults[.openWithRecentApps] = savedRecents
  }

  func testOpensAnExportedCopyWithTheChosenApplication() async throws {
    var opened: [(file: URL, app: URL)] = []
    let controller = OpenWithController(directory: directory, opener: { opened.append(($0, $1)) }, revealer: { _ in })
    let png = pngData()
    let item = imageItem(png)

    try await controller.open(item, with: preview)

    XCTAssertEqual(opened.count, 1)
    XCTAssertEqual(opened.first?.app, preview.url)
    XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(opened.first?.file)), png)
    XCTAssertEqual(opened.first?.file.pathExtension, "png")
    XCTAssertEqual(Defaults[.openWithRecentApps], [preview.url.path])
  }

  func testRecentApplicationsKeepTheLatestFirstWithoutDuplicates() async throws {
    let controller = OpenWithController(directory: directory, opener: { _, _ in }, revealer: { _ in })
    let other = OpenWithApplication(url: URL(fileURLWithPath: "/Applications/Skitch.app"), name: "Skitch",
                                    bundleIdentifier: "com.skitch.skitch")
    let item = imageItem(pngData())
    try await controller.open(item, with: preview)
    try await controller.open(item, with: other)
    try await controller.open(item, with: preview)
    XCTAssertEqual(Defaults[.openWithRecentApps], [preview.url.path, other.url.path])
  }

  func testDeletedItemIsNotOpened() async throws {
    var opened = 0
    let controller = OpenWithController(directory: directory, opener: { _, _ in opened += 1 }, revealer: { _ in })
    let item = imageItem(pngData())
    Storage.shared.context.delete(item.item)
    try Storage.shared.context.save()

    do {
      try await controller.open(item, with: preview)
      XCTFail("A deleted item must not be exported")
    } catch {}
    XCTAssertEqual(opened, 0)
  }

  func testRevealInFinderSelectsTheExportedCopy() async throws {
    var revealed: [URL] = []
    let controller = OpenWithController(directory: directory, opener: { _, _ in }, revealer: { revealed.append($0) })
    try await controller.revealInFinder(imageItem(pngData()))
    XCTAssertEqual(revealed.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(revealed.first).path))
  }

  func testUserCancellationIsNotReportedAsAnError() {
    XCTAssertTrue(OpenWithController.isUserCancellation(CocoaError(.userCancelled)))
    XCTAssertTrue(OpenWithController.isUserCancellation(NSError(domain: NSOSStatusErrorDomain, code: -128)))
    XCTAssertTrue(OpenWithController.isUserCancellation(NSError(
      domain: "com.apple.LaunchServices", code: 1,
      userInfo: [NSUnderlyingErrorKey: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)]
    )))
    XCTAssertFalse(OpenWithController.isUserCancellation(CocoaError(.fileReadNoPermission)))
  }

  func testRemoveAllCopiesEmptiesTheDirectory() async throws {
    let controller = OpenWithController(directory: directory, opener: { _, _ in }, revealer: { _ in })
    try await controller.revealInFinder(imageItem(pngData()))
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    controller.removeAllCopies()
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }

  private func pngData() -> Data {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 6, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
  }

  private func imageItem(_ png: Data) -> HistoryItemDecorator {
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [HistoryItemContent(type: NSPasteboard.PasteboardType.png.rawValue, value: png)]
    return HistoryItemDecorator(item)
  }
}
