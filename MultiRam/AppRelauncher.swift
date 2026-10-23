import AppKit
import os

// Restarts MultiRam in place. The new instance waits for the old one to quit, so two copies
// never register the hotkeys or poll the clipboard at the same time.
enum AppRelauncher {
  // LaunchServices drops launch arguments from sandboxed apps, so the old instance leaves
  // its process identifier in the shared defaults instead.
  static let requestKey = "relaunchRequest"
  static let requestLifetime: TimeInterval = 30

  typealias Open = (URL, NSWorkspace.OpenConfiguration, @escaping (Error?) -> Void) -> Void

  // True while the old instance quits for a relaunch; the session goes on in the new instance.
  private(set) static var isTerminatingForRelaunch = false

  private static let logger = Logger(subsystem: "local.multiram.MultiRam", category: "Relaunch")

  // Signal 0 only checks the process. The sandbox may refuse it with EPERM, which still means it exists.
  static func isProcessRunning(_ pid: pid_t) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
  }

  // Reads and removes the request left by `relaunch`. An old request belongs to a relaunch
  // that never happened and is ignored.
  static func takeRequest(from defaults: UserDefaults, now: Date) -> pid_t? {
    guard let request = defaults.dictionary(forKey: requestKey) else { return nil }
    defaults.removeObject(forKey: requestKey)
    guard let pid = request["pid"] as? Int, let date = request["date"] as? Date,
          abs(now.timeIntervalSince(date)) <= requestLifetime else {
      return nil
    }
    return pid_t(pid)
  }

  // Returns false when the process is still running after the timeout.
  static func waitForProcess(
    _ pid: pid_t,
    timeout: TimeInterval = 10,
    isRunning: (pid_t) -> Bool = isProcessRunning,
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) -> Bool {
    let step: TimeInterval = 0.05
    var waited: TimeInterval = 0
    while isRunning(pid) {
      guard waited < timeout else {
        logger.error("Previous instance \(pid) is still running, starting anyway")
        return false
      }
      sleep(step)
      waited += step
    }
    logger.notice("Previous instance \(pid) quit after \(waited, format: .fixed(precision: 2)) s")
    return true
  }

  // Called first thing at launch.
  static func finishRelaunch(defaults: UserDefaults = .standard) {
    guard let pid = takeRequest(from: defaults, now: Date()) else { return }
    _ = waitForProcess(pid)
  }

  @MainActor
  static func relaunch(
    bundleURL: URL = Bundle.main.bundleURL,
    processIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
    defaults: UserDefaults = .standard,
    now: Date = Date(),
    open: Open = { url, configuration, completion in
      NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in completion(error) }
    },
    terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
    failed: @escaping @MainActor (Error) -> Void = showFailure
  ) {
    defaults.set(["pid": Int(processIdentifier), "date": now], forKey: requestKey)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.activates = false
    logger.notice("Relaunching to pick up the Accessibility permission")
    open(bundleURL, configuration) { error in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          if let error {
            defaults.removeObject(forKey: requestKey)
            logger.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
            failed(error)
          } else {
            isTerminatingForRelaunch = true
            terminate()
            // NSApp.terminate returns only when termination was cancelled.
            isTerminatingForRelaunch = false
          }
        }
      }
    }
  }

  @MainActor
  private static func showFailure(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("accessibility_relaunch_failed_message", comment: "")
    alert.informativeText = NSLocalizedString("accessibility_relaunch_failed_comment", comment: "")
    NSApp.activate()
    alert.runModal()
  }
}
