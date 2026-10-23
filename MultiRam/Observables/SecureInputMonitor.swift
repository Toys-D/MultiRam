import AppKit
import Carbon.HIToolbox
import Observation

// Polls Secure Event Input so MultiRam can explain why an Option-only shortcut does not open it.
// Browsers turn it on while a password field has focus; nothing can override it.
@Observable
final class SecureInputMonitor {
  struct Snapshot: Equatable {
    var isEnabled: Bool
    var holderPID: pid_t?
  }

  static let shared = SecureInputMonitor()

  private(set) var isEnabled = false
  private(set) var holderName: String?

  @ObservationIgnored private let probe: () -> Snapshot
  @ObservationIgnored private let appName: (pid_t) -> String?
  @ObservationIgnored private var timer: Timer?

  init(
    probe: @escaping () -> Snapshot = SecureInputMonitor.systemSnapshot,
    appName: @escaping (pid_t) -> String? = { NSRunningApplication(processIdentifier: $0)?.localizedName }
  ) {
    self.probe = probe
    self.appName = appName
  }

  var isRunning: Bool { timer != nil }

  func start(interval: TimeInterval = 1) {
    guard timer == nil else { return }
    refresh()
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      self?.refresh()
    }
    timer.tolerance = interval / 2
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    update(isEnabled: false, holderName: nil)
  }

  func refresh() {
    let snapshot = probe()
    var holder: String?
    if snapshot.isEnabled, let pid = snapshot.holderPID, pid != ProcessInfo.processInfo.processIdentifier {
      holder = appName(pid)
    }
    update(isEnabled: snapshot.isEnabled, holderName: holder)
  }

  // Assign only on change so observers are not notified on every poll.
  private func update(isEnabled: Bool, holderName: String?) {
    if self.isEnabled != isEnabled {
      self.isEnabled = isEnabled
    }
    if self.holderName != holderName {
      self.holderName = holderName
    }
  }

  static func systemSnapshot() -> Snapshot {
    guard IsSecureEventInputEnabled() else {
      return Snapshot(isEnabled: false, holderPID: nil)
    }
    // The holder is published in the window server session; the key is undocumented but stable.
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    let pid = (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value
    return Snapshot(isEnabled: true, holderPID: pid)
  }
}
