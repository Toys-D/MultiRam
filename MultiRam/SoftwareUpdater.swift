import AppKit
import Defaults
import Observation
import os

struct ReleaseInfo: Equatable {
  let version: String
  let pageURL: URL
}

enum UpdateCheckResult: Equatable {
  case upToDate(String)
  case available(ReleaseInfo)
  case failed
}

enum ReleaseVersion {
  // "v1.4.0" and "1.4" become [1, 4, 0] and [1, 4]; anything else is not a version.
  static func components(_ string: String) -> [Int]? {
    let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
    let parts = trimmed.split(separator: ".").map { Int($0) }
    guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
    return parts.compactMap { $0 }
  }

  static func isNewer(_ candidate: String, than current: String) -> Bool {
    guard let candidate = components(candidate), let current = components(current) else { return false }
    for index in 0..<max(candidate.count, current.count) {
      let left = index < candidate.count ? candidate[index] : 0
      let right = index < current.count ? current[index] : 0
      if left != right { return left > right }
    }
    return false
  }
}

// Asks GitHub for the latest MultiRam release once a day and offers its download page.
// This is the only network request MultiRam makes; it can be turned off in Settings.
@Observable
final class SoftwareUpdater {
  static let shared = SoftwareUpdater()
  static let latestReleaseURL = URL(string: "https://api.github.com/repos/Toys-D/MultiRam/releases/latest")!
  static let checkInterval: TimeInterval = 24 * 60 * 60

  typealias Fetch = (URL) async throws -> Data

  let isAvailable = true
  private(set) var isChecking = false
  private(set) var lastResult: UpdateCheckResult?

  var automaticallyChecksForUpdates: Bool {
    get { access(keyPath: \.automaticallyChecksForUpdates); return Defaults[.checkForUpdates] }
    set { withMutation(keyPath: \.automaticallyChecksForUpdates) { Defaults[.checkForUpdates] = newValue } }
  }

  @ObservationIgnored private let currentVersion: String
  @ObservationIgnored private let fetch: Fetch
  @ObservationIgnored private var timer: Timer?
  @ObservationIgnored private let logger = Logger(subsystem: "local.multiram.MultiRam", category: "Updates")

  init(
    currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
    fetch: @escaping Fetch = SoftwareUpdater.download
  ) {
    self.currentVersion = currentVersion
    self.fetch = fetch
  }

  static func download(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("MultiRam", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return data
  }

  static func parse(_ data: Data) -> ReleaseInfo? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = json["tag_name"] as? String,
          let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
          json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
          let version = ReleaseVersion.components(tag) else {
      return nil
    }
    return ReleaseInfo(version: version.map(String.init).joined(separator: "."), pageURL: page)
  }

  static func shouldAnnounce(_ result: UpdateCheckResult, userInitiated: Bool, skippedVersion: String?) -> Bool {
    switch result {
    case .available(let info): return userInitiated || info.version != skippedVersion
    case .upToDate, .failed: return userInitiated
    }
  }

  static func isCheckDue(lastCheck: Date?, now: Date) -> Bool {
    guard let lastCheck else { return true }
    return now.timeIntervalSince(lastCheck) >= checkInterval
  }

  func check() async -> UpdateCheckResult {
    do {
      guard let release = Self.parse(try await fetch(Self.latestReleaseURL)) else { return .failed }
      return ReleaseVersion.isNewer(release.version, than: currentVersion)
        ? .available(release)
        : .upToDate(currentVersion)
    } catch {
      logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
      return .failed
    }
  }

  // Checks shortly after launch and then every few hours, at most once a day.
  @MainActor
  func start() {
    timer?.invalidate()
    let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkIfDue() }
    }
    timer.tolerance = 30 * 60
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      MainActor.assumeIsolated { self?.checkIfDue() }
    }
  }

  @MainActor
  func checkForUpdates() {
    Task { await checkAndAnnounce(userInitiated: true) }
  }

  @MainActor
  private func checkIfDue() {
    guard automaticallyChecksForUpdates,
          Self.isCheckDue(lastCheck: Defaults[.lastUpdateCheck], now: Date()) else { return }
    Task { await checkAndAnnounce(userInitiated: false) }
  }

  @MainActor
  private func checkAndAnnounce(userInitiated: Bool) async {
    guard !isChecking else { return }
    isChecking = true
    let result = await check()
    isChecking = false
    lastResult = result
    if result != .failed {
      Defaults[.lastUpdateCheck] = Date()
    }
    guard Self.shouldAnnounce(result, userInitiated: userInitiated, skippedVersion: Defaults[.skippedUpdateVersion])
    else { return }
    announce(result)
  }

  @MainActor
  private func announce(_ result: UpdateCheckResult) {
    let alert = NSAlert()
    switch result {
    case .available(let info):
      alert.messageText = String(format: NSLocalizedString("update_available_title", comment: ""), info.version)
      alert.informativeText = String(format: NSLocalizedString("update_available_message", comment: ""), currentVersion)
      alert.addButton(withTitle: NSLocalizedString("update_download", comment: ""))
      alert.addButton(withTitle: NSLocalizedString("update_later", comment: ""))
      alert.addButton(withTitle: NSLocalizedString("update_skip", comment: ""))
      NSApp.activate(ignoringOtherApps: true)
      switch alert.runModal() {
      case .alertFirstButtonReturn: NSWorkspace.shared.open(info.pageURL)
      case .alertThirdButtonReturn: Defaults[.skippedUpdateVersion] = info.version
      default: break
      }
    case .upToDate(let version):
      alert.messageText = NSLocalizedString("update_up_to_date", comment: "")
      alert.informativeText = String(format: NSLocalizedString("update_up_to_date_message", comment: ""), version)
      NSApp.activate(ignoringOtherApps: true)
      alert.runModal()
    case .failed:
      alert.messageText = NSLocalizedString("update_failed", comment: "")
      alert.informativeText = NSLocalizedString("update_failed_message", comment: "")
      NSApp.activate(ignoringOtherApps: true)
      alert.runModal()
    }
  }
}
