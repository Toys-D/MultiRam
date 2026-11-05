import SwiftUI
import Defaults
import KeyboardShortcuts
import LaunchAtLogin

struct GeneralSettingsPane: View {
  private let notificationsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "")"
  )

  @Default(.searchMode) private var searchMode

  @State private var copyModifier = HistoryItemAction.copy.modifierFlags.description
  @State private var pasteModifier = HistoryItemAction.paste.modifierFlags.description
  @State private var pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description

  @State private var updater = SoftwareUpdater.shared
  @State private var language = AppLanguage.selected(in: .standard, domain: Bundle.main.bundleIdentifier ?? "")

  var body: some View {
    SettingsPage(title: SettingsSection.general.title) {
      Form {
        Section {
          PasteAccessRow()
        }

        Section {
          LaunchAtLogin.Toggle {
            Text("LaunchAtLogin", tableName: "GeneralSettings")
          }
        }

        Section {
          Picker(selection: $language) {
            Text("language_system").tag(AppLanguage.system)
            Divider()
            ForEach(AppLanguage.choices, id: \.code) { choice in
              Text(verbatim: choice.name).tag(choice.code)
            }
          } label: {
            Text("language_title")
          }
          .onChange(of: language) {
            AppLanguage.select(language, in: .standard)
          }

          if AppLanguage.resolved(language) != AppLanguage.current {
            LabeledContent {
              Button(NSLocalizedString("language_restart_button", comment: "")) {
                AppRelauncher.relaunch()
              }
            } label: {
              Text("language_restart_hint")
            }
          }
        } footer: {
          Text("language_footer")
            .settingsFootnote()
        }

        Section {
          Toggle(isOn: $updater.automaticallyChecksForUpdates) {
            Text("CheckForUpdates", tableName: "GeneralSettings")
            Text("update_privacy")
          }
          LabeledContent {
            HStack(spacing: 10) {
              if updater.isChecking {
                ProgressView()
                  .controlSize(.small)
              }
              if case .available(let info) = updater.lastResult {
                Button(NSLocalizedString("update_download", comment: "")) {
                  NSWorkspace.shared.open(info.pageURL)
                }
              }
              Button {
                updater.checkForUpdates()
              } label: {
                Text("CheckNow", tableName: "GeneralSettings")
              }
              .disabled(updater.isChecking)
            }
          } label: {
            Text(updateStatus)
          }
        }

        Section {
          Defaults.Toggle(key: .pasteByDefault) {
            Text("PasteAutomatically", tableName: "GeneralSettings")
          }
          .onChange(refreshModifiers)

          Defaults.Toggle(key: .removeFormattingByDefault) {
            Text("PasteWithoutFormatting", tableName: "GeneralSettings")
          }
          .onChange(refreshModifiers)
        } header: {
          Text(settingsLabel("Behavior", table: "GeneralSettings"))
        } footer: {
          Text(String(
            format: NSLocalizedString("Modifiers", tableName: "GeneralSettings", comment: ""),
            copyModifier, pasteModifier, pasteWithoutFormatting
          ))
          .settingsFootnote()
        }

        Section {
          Picker(selection: $searchMode) {
            ForEach(Search.Mode.allCases) { mode in
              Text(mode.description)
            }
          } label: {
            Text(settingsLabel("Search", table: "GeneralSettings"))
          }

          if let notificationsURL {
            LabeledContent {
              Link(destination: notificationsURL) {
                Image(systemName: "arrow.up.forward.app")
              }
            } label: {
              Text(settingsLabel("NotificationsAndSounds", table: "GeneralSettings"))
            }
          }
        }
      }
      .formStyle(.grouped)
    }
  }

  private var updateStatus: String {
    switch updater.lastResult {
    case .available(let info):
      return String(format: NSLocalizedString("update_available_title", comment: ""), info.version)
    case .upToDate:
      return NSLocalizedString("update_up_to_date", comment: "")
    case .failed:
      return NSLocalizedString("update_failed", comment: "")
    case nil:
      return About.version
    }
  }

  private func refreshModifiers(_ sender: Sendable) {
    copyModifier = HistoryItemAction.copy.modifierFlags.description
    pasteModifier = HistoryItemAction.paste.modifierFlags.description
    pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description
  }
}

// Shows whether MultiRam may paste for the user and offers the one action that fixes it.
struct PasteAccessRow: View {
  @State private var access = Accessibility.currentAccess()
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    LabeledContent {
      HStack(spacing: 10) {
        Label {
          Text(statusText)
        } icon: {
          Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
        }
        .foregroundStyle(access == .granted ? .primary : .secondary)

        switch access {
        case .granted:
          EmptyView()
        case .needsPermission:
          Button(NSLocalizedString("paste_access_allow", comment: "")) {
            Accessibility.requestPermission()
          }
        case .needsRelaunch:
          Button(NSLocalizedString("paste_access_restart", comment: "")) {
            AppRelauncher.relaunch()
          }
        }
      }
    } label: {
      Text("paste_access_title")
      if let hint {
        Text(hint)
      }
    }
    .onReceive(timer) { _ in
      access = Accessibility.currentAccess()
    }
    .accessibilityIdentifier("paste-access-status")
  }

  private var statusText: String {
    switch access {
    case .granted: return NSLocalizedString("paste_access_granted", comment: "")
    case .needsPermission: return NSLocalizedString("paste_access_missing", comment: "")
    case .needsRelaunch: return NSLocalizedString("paste_access_relaunch", comment: "")
    }
  }

  private var statusColor: Color {
    switch access {
    case .granted: return .green
    case .needsPermission: return .red
    case .needsRelaunch: return .orange
    }
  }

  private var hint: String? {
    switch access {
    case .granted: return nil
    case .needsPermission: return Accessibility.localized("paste_access_hint_missing")
    case .needsRelaunch: return NSLocalizedString("paste_access_hint_relaunch", comment: "")
    }
  }
}

struct ShortcutsSettingsPane: View {
  @State private var popupShortcut = KeyboardShortcuts.getShortcut(for: .popup)
  @State private var fallbackShortcut = KeyboardShortcuts.getShortcut(for: .popupFallback)

  private var fallbackWorksInPasswordFields: Bool {
    fallbackShortcut != nil && !HotkeySecurity.isBlockedBySecureInput(fallbackShortcut)
  }

  var body: some View {
    SettingsPage(title: SettingsSection.shortcuts.title) {
      Form {
        Section {
          LabeledContent {
            KeyboardShortcuts.Recorder(for: .popup, onChange: { newShortcut in
              refreshShortcuts()
              if newShortcut == nil {
                // No shortcut is recorded. Remove keys monitor
                AppState.shared.popup.deinitEventsMonitor()
              } else {
                // User is using shortcut. Ensure keys monitor is initialized
                AppState.shared.popup.initEventsMonitor()
              }
            })
            .help(Text("OpenTooltip", tableName: "GeneralSettings"))
          } label: {
            Text(settingsLabel("Open", table: "GeneralSettings"))
            if HotkeySecurity.isBlockedBySecureInput(popupShortcut) {
              Text(fallbackWorksInPasswordFields ? "OptionOnlyWarning" : "OptionOnlyWarningNoFallback",
                   tableName: "GeneralSettings")
            }
          }

          LabeledContent {
            KeyboardShortcuts.Recorder(for: .popupFallback, onChange: { _ in refreshShortcuts() })
              .help(Text("OpenFallbackTooltip", tableName: "GeneralSettings"))
          } label: {
            Text(settingsLabel("OpenFallback", table: "GeneralSettings"))
            if HotkeySecurity.isBlockedBySecureInput(fallbackShortcut) {
              Text("FallbackBlockedWarning", tableName: "GeneralSettings")
            }
          }
        }

        Section {
          LabeledContent {
            KeyboardShortcuts.Recorder(for: .pin)
              .help(Text("PinTooltip", tableName: "GeneralSettings"))
          } label: {
            Text(settingsLabel("Pin", table: "GeneralSettings"))
          }

          LabeledContent {
            KeyboardShortcuts.Recorder(for: .delete)
              .help(Text("DeleteTooltip", tableName: "GeneralSettings"))
          } label: {
            Text(settingsLabel("Delete", table: "GeneralSettings"))
          }
        } footer: {
          Text("shortcuts_hint")
            .settingsFootnote()
        }
      }
      .formStyle(.grouped)
    }
  }

  // Equal shortcuts would cancel each other out, so the fallback is cleared; then the warnings update.
  private func refreshShortcuts() {
    Popup.resolveShortcutConflict()
    popupShortcut = KeyboardShortcuts.getShortcut(for: .popup)
    fallbackShortcut = KeyboardShortcuts.getShortcut(for: .popupFallback)
  }
}

#Preview {
  GeneralSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
