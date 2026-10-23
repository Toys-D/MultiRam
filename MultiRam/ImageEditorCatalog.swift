import AppKit
import Defaults
import UniformTypeIdentifiers

struct OpenWithApplication: Identifiable, Hashable {
  let url: URL
  let name: String
  let bundleIdentifier: String?

  var id: String { url.path }
}

struct OpenWithApplications: Equatable {
  // Image editors and viewers, default application first.
  var featured: [OpenWithApplication] = []
  // Everything Launch Services offers for the type.
  var all: [OpenWithApplication] = []
}

// The parts of an application's Info.plist that tell whether it edits images.
struct AppMetadata: Equatable {
  struct DocumentType: Equatable {
    var role: String?
    var rank: String?
    var contentTypes: [String]
    var extensions: [String]

    init(role: String? = nil, rank: String? = nil, contentTypes: [String] = [], extensions: [String] = []) {
      self.role = role
      self.rank = rank
      self.contentTypes = contentTypes
      self.extensions = extensions
    }
  }

  var bundleIdentifier: String?
  var category: String?
  var isAgent: Bool
  var documentTypes: [DocumentType]

  init(bundleIdentifier: String? = nil, category: String? = nil, isAgent: Bool = false,
       documentTypes: [DocumentType] = []) {
    self.bundleIdentifier = bundleIdentifier
    self.category = category
    self.isAgent = isAgent
    self.documentTypes = documentTypes
  }

  init(infoDictionary info: [String: Any]) {
    func flag(_ key: String) -> Bool {
      if let value = info[key] as? Bool { return value }
      if let value = info[key] as? String { return ["1", "yes", "true"].contains(value.lowercased()) }
      return false
    }

    let types = info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
    self.init(
      bundleIdentifier: info["CFBundleIdentifier"] as? String,
      category: info["LSApplicationCategoryType"] as? String,
      isAgent: flag("LSUIElement") || flag("LSBackgroundOnly"),
      documentTypes: types.map { type in
        DocumentType(
          role: type["CFBundleTypeRole"] as? String,
          rank: type["LSHandlerRank"] as? String,
          contentTypes: type["LSItemContentTypes"] as? [String] ?? [],
          extensions: type["CFBundleTypeExtensions"] as? [String] ?? []
        )
      }
    )
  }
}

protocol ApplicationProvider {
  func applications(toOpen type: UTType) -> [URL]
  func defaultApplication(toOpen type: UTType) -> URL?
  func browserApplications() -> [URL]
  func metadata(for appURL: URL) -> AppMetadata?
  func displayName(for appURL: URL) -> String
  func applicationExists(at appURL: URL) -> Bool
}

struct WorkspaceApplicationProvider: ApplicationProvider {
  func applications(toOpen type: UTType) -> [URL] {
    NSWorkspace.shared.urlsForApplications(toOpen: type)
  }

  func defaultApplication(toOpen type: UTType) -> URL? {
    NSWorkspace.shared.urlForApplication(toOpen: type)
  }

  func browserApplications() -> [URL] {
    guard let url = URL(string: "https://example.com") else { return [] }
    return NSWorkspace.shared.urlsForApplications(toOpen: url)
  }

  // The sandbox can read bundles in /Applications and /System only; others return nil.
  func metadata(for appURL: URL) -> AppMetadata? {
    Bundle(url: appURL)?.infoDictionary.map(AppMetadata.init(infoDictionary:))
  }

  // The sandbox allows reading file metadata anywhere, so this also works for ~/Applications.
  func applicationExists(at appURL: URL) -> Bool {
    FileManager.default.fileExists(atPath: appURL.path)
  }

  // Localized, e.g. "Просмотр" for Preview in Russian.
  func displayName(for appURL: URL) -> String {
    let name = FileManager.default.displayName(atPath: appURL.path)
    return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
  }
}

// Finds the apps worth offering for an image: graphics and photo editors plus the default viewer.
// Launch Services also offers browsers, messengers and players for images, so they are filtered out.
final class ImageEditorCatalog {
  static let shared = ImageEditorCatalog(
    provider: WorkspaceApplicationProvider(),
    ownBundleIdentifier: Bundle.main.bundleIdentifier,
    recentPaths: { Defaults[.openWithRecentApps] }
  )

  private static let editedTypes: [UTType] = [.png, .jpeg, .tiff]
  private static let editedExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff"]
  private static let broadTypes: Set<String> = ["public.data", "public.item", "public.content", "*", "****"]
  private static let creativeCategories: Set<String> = [
    "public.app-category.graphics-design", "public.app-category.photography"
  ]
  private static let unrelatedCategories: Set<String> = [
    "public.app-category.social-networking", "public.app-category.developer-tools",
    "public.app-category.video", "public.app-category.music", "public.app-category.games",
    "public.app-category.entertainment", "public.app-category.business", "public.app-category.finance",
    "public.app-category.utilities", "public.app-category.news", "public.app-category.reference",
    "public.app-category.education", "public.app-category.lifestyle", "public.app-category.weather",
    "public.app-category.travel", "public.app-category.sports", "public.app-category.medical",
    "public.app-category.healthcare-fitness"
  ]
  private static let throwawayLocations = ["/Library/Caches/", "/DerivedData/", "/.Trash/", "/AppTranslocation/"]

  private let provider: ApplicationProvider
  private let ownBundleIdentifier: String?
  private let recentPaths: () -> [String]
  private var cache: [UTType: OpenWithApplications] = [:]

  init(provider: ApplicationProvider, ownBundleIdentifier: String?, recentPaths: @escaping () -> [String]) {
    self.provider = provider
    self.ownBundleIdentifier = ownBundleIdentifier
    self.recentPaths = recentPaths
  }

  func applications(for type: UTType) -> OpenWithApplications {
    if let cached = cache[type] {
      return cached
    }
    let applications = findApplications(for: type)
    cache[type] = applications
    return applications
  }

  // Called when the order may change (an app was used) or new apps may have been installed.
  func invalidate() {
    cache = [:]
  }

  static func claimsImageEditing(_ metadata: AppMetadata) -> Bool {
    metadata.documentTypes.contains { type in
      guard type.role == "Editor", type.rank != "Alternate" else { return false }
      let matchesType = type.contentTypes.contains { identifier in
        guard !broadTypes.contains(identifier), let declared = UTType(identifier) else { return false }
        return editedTypes.contains { $0.conforms(to: declared) }
      }
      let matchesExtension = type.extensions.contains { editedExtensions.contains($0.lowercased()) }
      return matchesType || matchesExtension
    }
  }

  private func findApplications(for type: UTType) -> OpenWithApplications {
    let defaultApp = provider.defaultApplication(toOpen: type)?.standardizedFileURL
    var seen = Set<String>()
    var candidates: [URL] = []
    for url in [defaultApp].compactMap({ $0 }) + provider.applications(toOpen: type) {
      let url = url.standardizedFileURL
      guard seen.insert(url.path).inserted, !Self.isThrowaway(url) else { continue }
      if let own = ownBundleIdentifier, provider.metadata(for: url)?.bundleIdentifier == own { continue }
      candidates.append(url)
    }

    let browsers = Set(provider.browserApplications().map { $0.standardizedFileURL.path })
    let editors = candidates.filter { url in
      url == defaultApp || isImageEditor(url, browsers: browsers)
    }

    let recent = recentPaths()
    // Apps the user chose for images before are offered again even if they do not look like editors,
    // for example ones picked with Other Application… or whose Info.plist the sandbox cannot read.
    let editorPaths = Set(editors.map(\.path))
    let chosen = recent.compactMap { path -> URL? in
      let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
      guard !editorPaths.contains(url.path), !Self.isThrowaway(url), provider.applicationExists(at: url) else {
        return nil
      }
      if let own = ownBundleIdentifier, provider.metadata(for: url)?.bundleIdentifier == own { return nil }
      return url
    }
    let ordered = (editors + chosen).enumerated().sorted { lhs, rhs in
      let left = rank(lhs.element, defaultApp: defaultApp, recent: recent)
      let right = rank(rhs.element, defaultApp: defaultApp, recent: recent)
      return left != right ? left < right : lhs.offset < rhs.offset
    }.map(\.element)

    return OpenWithApplications(featured: ordered.map(application), all: candidates.map(application))
  }

  private func isImageEditor(_ url: URL, browsers: Set<String>) -> Bool {
    guard !browsers.contains(url.path), let metadata = provider.metadata(for: url), !metadata.isAgent else {
      return false
    }
    if let category = metadata.category {
      if Self.unrelatedCategories.contains(category) { return false }
      if Self.creativeCategories.contains(category) { return true }
    }
    return Self.claimsImageEditing(metadata)
  }

  // Default first, then recently used apps, then graphics and photo apps, then the rest.
  private func rank(_ url: URL, defaultApp: URL?, recent: [String]) -> Int {
    if url == defaultApp { return 0 }
    if let index = recent.firstIndex(of: url.path) { return 1 + index }
    let category = provider.metadata(for: url)?.category
    return recent.count + (category.map(Self.creativeCategories.contains) == true ? 1 : 2)
  }

  private func application(_ url: URL) -> OpenWithApplication {
    OpenWithApplication(
      url: url,
      name: provider.displayName(for: url),
      bundleIdentifier: provider.metadata(for: url)?.bundleIdentifier
    )
  }

  // Copies in caches, the Trash or translocation folders, and helpers inside other app bundles.
  private static func isThrowaway(_ url: URL) -> Bool {
    let path = url.path
    if throwawayLocations.contains(where: path.contains) { return true }
    return url.deletingLastPathComponent().pathComponents.contains { $0.hasSuffix(".app") }
  }
}
