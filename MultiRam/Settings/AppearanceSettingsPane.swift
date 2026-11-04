import AppKit
import SwiftUI
import Defaults

struct HistoryWindowSettingsPane: View {
  @Default(.popupPosition) private var popupAt
  @Default(.popupScreen) private var popupScreen
  @Default(.pinTo) private var pinTo
  @Default(.imageMaxHeight) private var imageHeight
  @Default(.highlightMatch) private var highlightMatch
  @Default(.showSearch) private var showSearch
  @Default(.searchVisibility) private var searchVisibility
  @Default(.windowPosition) private var windowPosition

  @State private var screens = NSScreen.screens

  private let imageHeightFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 200
    return formatter
  }()

  var body: some View {
    SettingsPage(title: SettingsSection.historyWindow.title) {
      Form {
        Section {
          LabeledContent {
            HStack {
              if popupAt == .lastPosition {
                Button {
                  _windowPosition.reset()
                } label: {
                  Image(systemName: "arrow.uturn.backward.circle.fill")
                    .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .help(Text("PopupAtLastLocationReset", tableName: "AppearanceSettings"))
                .disabled(windowPosition == _windowPosition.defaultValue)
              }

              Picker("", selection: $popupAt) {
                ForEach(PopupPosition.allCases) { position in
                  if position == .center || position == .lastPosition, screens.count > 1 {
                    screenPicker(for: position)
                  } else {
                    Text(position.description)
                  }
                }
              }
              .labelsHidden()
              .fixedSize()
              .help(Text("PopupAtTooltip", tableName: "AppearanceSettings"))
            }
          } label: {
            Text(settingsLabel("PopupAt", table: "AppearanceSettings"))
          }

          Picker(selection: $pinTo) {
            ForEach(PinsPosition.allCases) { position in
              Text(position.description)
            }
          } label: {
            Text(settingsLabel("PinTo", table: "AppearanceSettings"))
          }
          .help(Text("PinToTooltip", tableName: "AppearanceSettings"))

          LabeledContent {
            HStack {
              TextField("", value: $imageHeight, formatter: imageHeightFormatter)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .help(Text("ImageHeightTooltip", tableName: "AppearanceSettings"))
              Stepper("", value: $imageHeight, in: 1...200)
                .labelsHidden()
            }
          } label: {
            Text(settingsLabel("ImageHeight", table: "AppearanceSettings"))
          }

          Picker(selection: $highlightMatch) {
            ForEach(HighlightMatch.allCases) { match in
              Text(match.description)
            }
          } label: {
            Text(settingsLabel("HighlightMatches", table: "AppearanceSettings"))
          }
          .help(Text("HighlightMatchesTooltip", tableName: "AppearanceSettings"))
        }

        Section {
          LabeledContent {
            HStack {
              Picker("", selection: $searchVisibility) {
                ForEach(SearchVisibility.allCases) { type in
                  Text(type.description)
                }
              }
              .labelsHidden()
              .fixedSize()
              .disabled(!showSearch)

              Toggle("", isOn: $showSearch)
                .labelsHidden()
            }
          } label: {
            Text("ShowSearchField", tableName: "AppearanceSettings")
          }

          Defaults.Toggle(key: .showTitle) {
            Text("ShowTitleBeforeSearchField", tableName: "AppearanceSettings")
          }
          Defaults.Toggle(key: .showApplicationIcons) {
            Text("ShowApplicationIcons", tableName: "AppearanceSettings")
          }
          Defaults.Toggle(key: .showSpecialSymbols) {
            Text("ShowSpecialSymbols", tableName: "AppearanceSettings")
          }
          .help(Text("ShowSpecialSymbolsTooltip", tableName: "AppearanceSettings"))
        }
      }
      .formStyle(.grouped)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
      screens = NSScreen.screens
    }
  }

  @ViewBuilder
  private func screenPicker(for position: PopupPosition) -> some View {
    let screenBinding: Binding<Int> = Binding {
      return popupScreen
    } set: {
      popupScreen = $0
      popupAt = position
    }

    Picker(selection: screenBinding) {
      Text(labelForScreen(index: 0))
        .tag(0)

      ForEach(screens.indices, id: \.self) { index in
        Text(labelForScreen(index: index + 1))
          .tag(index + 1)
      }
    } label: {
      if popupAt == position {
        Text("\(position.description) (\(labelForScreen(index: popupScreen)))")
      } else {
        Text(position.description)
      }
    }
  }

  private func labelForScreen(index screenIndex: Int) -> String {
    switch screenIndex {
    case 0:
      return String(localized: "ActiveScreen", table: "AppearanceSettings")
    case _:
      return screens[screenIndex - 1].localizedName
    }
  }
}

struct MenuBarSettingsPane: View {
  @Default(.menuIcon) private var menuIcon
  @Default(.showInStatusBar) private var showInStatusBar

  var body: some View {
    SettingsPage(title: SettingsSection.menuBar.title) {
      Form {
        Section {
          LabeledContent {
            HStack {
              Picker("", selection: $menuIcon) {
                ForEach(MenuIcon.allCases) { icon in
                  Image(nsImage: icon.image)
                }
              }
              .labelsHidden()
              .fixedSize()
              .disabled(!showInStatusBar)

              Toggle("", isOn: $showInStatusBar)
                .labelsHidden()
            }
          } label: {
            Text("ShowMenuIcon", tableName: "AppearanceSettings")
          }

          Defaults.Toggle(key: .showRecentCopyInMenuBar) {
            Text("ShowRecentCopyInMenuBar", tableName: "AppearanceSettings")
          }
        }
      }
      .formStyle(.grouped)
    }
  }
}

#Preview {
  HistoryWindowSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
