import Foundation
import Observation

#if canImport(Sparkle)
import Sparkle

@Observable
class SoftwareUpdater {
  var automaticallyChecksForUpdates = false {
    didSet {
      updater?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  var isAvailable: Bool { updater != nil }

  private var updater: SPUUpdater?
  private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?
  private var updaterController: SPUStandardUpdaterController?

  init() {
    // A renamed app must never install releases from the upstream application's feed.
    guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
          let feedURL = URL(string: feed), feedURL.scheme == "https", feedURL.host != nil else { return }

    let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    updaterController = controller
    let updater = controller.updater
    self.updater = updater
    automaticallyChecksForUpdatesObservation = updater.observe(
      \.automaticallyChecksForUpdates,
      options: [.initial, .new, .old]
    ) { [unowned self] updater, change in
      guard change.newValue != change.oldValue else {
        return
      }

      self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }
  }

  func checkForUpdates() {
    updater?.checkForUpdates()
  }
}
#else
// The portable release has no update feed or dynamic updater dependency.
// Re-enable the integration only with a distribution signing identity.
@Observable
class SoftwareUpdater {
  let isAvailable = false
  var automaticallyChecksForUpdates = false

  func checkForUpdates() {}
}
#endif
