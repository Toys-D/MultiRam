import SwiftUI
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Settings

struct GeneralSettingsPane: View {
  private let notificationsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "")"
  )

  @Default(.searchMode) private var searchMode

  @State private var copyModifier = HistoryItemAction.copy.modifierFlags.description
  @State private var pasteModifier = HistoryItemAction.paste.modifierFlags.description
  @State private var pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description

  @State private var updater = SoftwareUpdater()
  @State private var popupShortcut = KeyboardShortcuts.getShortcut(for: .popup)
  @State private var fallbackShortcut = KeyboardShortcuts.getShortcut(for: .popupFallback)

  private var fallbackWorksInPasswordFields: Bool {
    fallbackShortcut != nil && !HotkeySecurity.isBlockedBySecureInput(fallbackShortcut)
  }

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(title: "", bottomDivider: true) {
        LaunchAtLogin.Toggle {
          Text("LaunchAtLogin", tableName: "GeneralSettings")
        }
        if updater.isAvailable {
          Toggle(isOn: $updater.automaticallyChecksForUpdates) {
            Text("CheckForUpdates", tableName: "GeneralSettings")
          }
          Button(
            action: { updater.checkForUpdates() },
            label: { Text("CheckNow", tableName: "GeneralSettings") }
          )
        }
      }

      Settings.Section(label: { Text("Open", tableName: "GeneralSettings") }) {
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
        if HotkeySecurity.isBlockedBySecureInput(popupShortcut) {
          Text(fallbackWorksInPasswordFields ? "OptionOnlyWarning" : "OptionOnlyWarningNoFallback",
               tableName: "GeneralSettings")
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280, alignment: .leading)
            .foregroundStyle(.gray)
            .controlSize(.small)
        }
      }

      Settings.Section(label: { Text("OpenFallback", tableName: "GeneralSettings") }) {
        KeyboardShortcuts.Recorder(for: .popupFallback, onChange: { _ in refreshShortcuts() })
          .help(Text("OpenFallbackTooltip", tableName: "GeneralSettings"))
        if HotkeySecurity.isBlockedBySecureInput(fallbackShortcut) {
          Text("FallbackBlockedWarning", tableName: "GeneralSettings")
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280, alignment: .leading)
            .foregroundStyle(.gray)
            .controlSize(.small)
        }
      }

      Settings.Section(label: { Text("Pin", tableName: "GeneralSettings") }) {
        KeyboardShortcuts.Recorder(for: .pin)
          .help(Text("PinTooltip", tableName: "GeneralSettings"))
      }
      Settings.Section(bottomDivider: true, label: { Text("Delete", tableName: "GeneralSettings") }
      ) {
        KeyboardShortcuts.Recorder(for: .delete)
          .help(Text("DeleteTooltip", tableName: "GeneralSettings"))
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Search", tableName: "GeneralSettings") }
      ) {
        Picker("", selection: $searchMode) {
          ForEach(Search.Mode.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 180, alignment: .leading)
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Behavior", tableName: "GeneralSettings") }
      ) {
        Defaults.Toggle(key: .pasteByDefault) {
          Text("PasteAutomatically", tableName: "GeneralSettings")
        }
        .onChange(refreshModifiers)
        .fixedSize()

        Defaults.Toggle(key: .removeFormattingByDefault) {
          Text("PasteWithoutFormatting", tableName: "GeneralSettings")
        }
        .onChange(refreshModifiers)
        .fixedSize()

        Text(String(
          format: NSLocalizedString("Modifiers", tableName: "GeneralSettings", comment: ""),
          copyModifier, pasteModifier, pasteWithoutFormatting
        ))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      }

      Settings.Section(title: "") {
        if let notificationsURL = notificationsURL {
          Link(destination: notificationsURL, label: {
            Text("NotificationsAndSounds", tableName: "GeneralSettings")
          })
        }
      }
    }
  }

  // Equal shortcuts would cancel each other out, so the fallback is cleared; then the warnings update.
  private func refreshShortcuts() {
    Popup.resolveShortcutConflict()
    popupShortcut = KeyboardShortcuts.getShortcut(for: .popup)
    fallbackShortcut = KeyboardShortcuts.getShortcut(for: .popupFallback)
  }

  private func refreshModifiers(_ sender: Sendable) {
    copyModifier = HistoryItemAction.copy.modifierFlags.description
    pasteModifier = HistoryItemAction.paste.modifierFlags.description
    pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description
  }
}

#Preview {
  GeneralSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
