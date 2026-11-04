import SwiftUI

struct IgnoreSettingsPane: View {
  private enum Tab: Hashable {
    case applications, pasteboardTypes, regexps
  }

  @State private var tab = Tab.applications

  var body: some View {
    SettingsPage(title: SettingsSection.ignore.title) {
      VStack(alignment: .leading, spacing: 12) {
        Picker("", selection: $tab) {
          Text("ApplicationsTab", tableName: "IgnoreSettings").tag(Tab.applications)
          Text("PasteboardTypesTab", tableName: "IgnoreSettings").tag(Tab.pasteboardTypes)
          Text("RegexpTab", tableName: "IgnoreSettings").tag(Tab.regexps)
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        SettingsPanel {
          switch tab {
          case .applications: IgnoreApplicationsSettingsView()
          case .pasteboardTypes: IgnorePasteboardTypesSettingsView()
          case .regexps: IgnoreRegexpsSettingsView()
          }
        }
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 18)
    }
  }
}

#Preview {
  IgnoreSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
