import AppKit
import Defaults
import UniformTypeIdentifiers

enum OpenWithError: LocalizedError {
  case noImage

  var errorDescription: String? {
    NSLocalizedString("open_with_failed", comment: "")
  }
}

// Opens a copy of a clipboard image in another application.
@MainActor
final class OpenWithController {
  typealias Opener = @MainActor (_ file: URL, _ application: URL) async throws -> Void
  typealias Revealer = @MainActor (_ file: URL) -> Void
  typealias Liveness = @MainActor (_ item: HistoryItemDecorator) -> Bool

  static let shared = OpenWithController()
  private static let maximumRecentApplications = 6
  private static let copyLifetime: TimeInterval = 86_400

  private let directory: URL
  private let opener: Opener
  private let revealer: Revealer
  private let isAlive: Liveness

  init(
    directory: URL = ImageExport.defaultDirectory,
    opener: @escaping Opener = { try await OpenWithController.openInWorkspace($0, with: $1) },
    revealer: @escaping Revealer = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
    isAlive: @escaping Liveness = { AppState.shared.history.all.contains($0) }
  ) {
    self.directory = directory
    self.opener = opener
    self.revealer = revealer
    self.isAlive = isAlive
  }

  func open(_ item: HistoryItemDecorator, with application: OpenWithApplication) async throws {
    let file = try await exportedFile(for: item)
    try await opener(file, application.url)
    remember(application)
  }

  func revealInFinder(_ item: HistoryItemDecorator) async throws {
    revealer(try await exportedFile(for: item))
  }

  // Lets the user pick any application. MultiRam is an agent app, so it activates itself first
  // to bring the panel to the front.
  func chooseApplication(for item: HistoryItemDecorator) async throws {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.allowedContentTypes = [.application]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.treatsFilePackagesAsDirectories = false
    let previous = Self.frontmostOtherApplication()
    NSApp.activate()
    guard panel.runModal() == .OK, let url = panel.url else {
      Self.restoreFocus(to: previous)
      return
    }
    // The item may have been deleted while the panel was open.
    guard isAlive(item) else {
      Self.restoreFocus(to: previous)
      throw OpenWithError.noImage
    }

    let application = OpenWithApplication(
      url: url,
      name: WorkspaceApplicationProvider().displayName(for: url),
      bundleIdentifier: Bundle(url: url)?.bundleIdentifier
    )
    try await open(item, with: application)
  }

  func purgeOldCopies() {
    let directory = self.directory
    Task.detached(priority: .utility) {
      ImageExport.purge(directory, olderThan: Self.copyLifetime)
    }
  }

  // Synchronous, for use when the app quits.
  func purgeOldCopiesNow() {
    ImageExport.purge(directory, olderThan: Self.copyLifetime)
  }

  // Called when the history is cleared, so copies of cleared images do not outlive it.
  func removeAllCopies() {
    ImageExport.removeAll(in: directory)
  }

  // A cancelled first-launch or permission prompt is the user's choice, not a failure.
  static func isUserCancellation(_ error: Error) -> Bool {
    func isCancel(_ error: NSError) -> Bool {
      (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)
        || (error.domain == NSOSStatusErrorDomain && error.code == userCanceledErr)
    }
    let error = error as NSError
    if isCancel(error) { return true }
    return (error.userInfo[NSUnderlyingErrorKey] as? NSError).map(isCancel) ?? false
  }

  static func present(_ error: Error) {
    guard !isUserCancellation(error) else { return }
    let previous = frontmostOtherApplication()
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("open_with_failed", comment: "")
    alert.informativeText = (error as? OpenWithError) == nil ? error.localizedDescription : ""
    NSApp.activate()
    alert.runModal()
    restoreFocus(to: previous)
  }

  // The popup never takes focus, so the app the user was working in is still frontmost here.
  private static func frontmostOtherApplication() -> NSRunningApplication? {
    let application = NSWorkspace.shared.frontmostApplication
    return application == NSRunningApplication.current ? nil : application
  }

  // MultiRam has no windows left after a modal panel, so focus goes back to that app.
  private static func restoreFocus(to application: NSRunningApplication?) {
    guard let application, !application.isTerminated else { return }
    NSApp.yieldActivation(to: application)
    application.activate()
  }

  static func openInWorkspace(_ file: URL, with application: URL) async throws {
    // Under cooperative activation the opened app comes forward only if we yield to it.
    if let identifier = Bundle(url: application)?.bundleIdentifier {
      NSApp.yieldActivation(toApplicationWithBundleIdentifier: identifier)
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.addsToRecentItems = false
    configuration.promptsUserIfNeeded = true
    _ = try await NSWorkspace.shared.open([file], withApplicationAt: application, configuration: configuration)
  }

  // Model data is read on the main actor; conversion and writing happen in the background.
  private func exportedFile(for item: HistoryItemDecorator) async throws -> URL {
    guard let representation = ImageExport.representation(of: item.item) else {
      throw OpenWithError.noImage
    }
    let name = ImageExport.fileName(for: item.item)
    let directory = self.directory
    return try await Task.detached(priority: .userInitiated) {
      ImageExport.purge(directory, olderThan: Self.copyLifetime)
      return try ImageExport.write(ImageExport.exportable(representation), name: name, in: directory)
    }.value
  }

  private func remember(_ application: OpenWithApplication) {
    var recent = Defaults[.openWithRecentApps].filter { $0 != application.url.path }
    recent.insert(application.url.path, at: 0)
    Defaults[.openWithRecentApps] = Array(recent.prefix(Self.maximumRecentApplications))
    ImageEditorCatalog.shared.invalidate()
  }
}
