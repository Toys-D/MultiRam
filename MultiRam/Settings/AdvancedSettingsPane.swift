import SwiftUI
import Defaults

struct AdvancedSettingsPane: View {
  var body: some View {
    SettingsPage(title: SettingsSection.privacy.title) {
      Form {
        Section {
          Defaults.Toggle(key: .ignoreEvents) {
            Text("TurnOff", tableName: "AdvancedSettings")
            Text("TurnOffDescription", tableName: "AdvancedSettings")
          }
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            script("TurnOffShellScript")
            Text("TurnOffViaMenuIconDescription", tableName: "AdvancedSettings")
              .settingsFootnote()
            script("TurnOffNextShellScript")
          }
        }

        Section {
          Defaults.Toggle(key: .clearOnQuit) {
            Text("ClearHistoryOnQuit", tableName: "AdvancedSettings")
          }
          .help(Text("ClearHistoryOnQuitTooltip", tableName: "AdvancedSettings"))

          Defaults.Toggle(key: .clearSystemClipboard) {
            Text("ClearSystemClipboard", tableName: "AdvancedSettings")
          }
          .help(Text("ClearSystemClipboardTooltip", tableName: "AdvancedSettings"))
        }
      }
      .formStyle(.grouped)
    }
  }

  private func script(_ key: String) -> some View {
    Text(LocalizedStringKey(key), tableName: "AdvancedSettings")
      .font(.system(size: 11, design: .monospaced))
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
  }
}

#Preview {
  AdvancedSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
