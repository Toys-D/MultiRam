import SwiftUI
import Defaults

struct StorageSettingsPane: View {
  @Observable
  class ViewModel {
    var saveFiles = false {
      didSet {
        Defaults.withoutPropagation {
          if saveFiles {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.files.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.files.types)
          }
        }
      }
    }

    var saveImages = false {
      didSet {
        Defaults.withoutPropagation {
          if saveImages {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.images.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.images.types)
          }
        }
      }
    }

    var saveText = false {
      didSet {
        Defaults.withoutPropagation {
          if saveText {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.text.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.text.types)
          }
        }
      }
    }

    private var observer: Defaults.Observation?

    init() {
      observer = Defaults.observe(.enabledPasteboardTypes) { change in
        self.saveFiles = change.newValue.isSuperset(of: StorageType.files.types)
        self.saveImages = change.newValue.isSuperset(of: StorageType.images.types)
        self.saveText = change.newValue.isSuperset(of: StorageType.text.types)
      }
    }

    deinit {
      observer?.invalidate()
    }
  }

  @Default(.size) private var size
  @Default(.sortBy) private var sortBy
  @Default(.historyRetention) private var retention

  @State private var viewModel = ViewModel()
  @State private var storageSize = Storage.shared.size

  private let sizeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 999
    return formatter
  }()

  var body: some View {
    SettingsPage(title: SettingsSection.storage.title) {
      Form {
        Section {
          Toggle(isOn: $viewModel.saveFiles) { Text("Files", tableName: "StorageSettings") }
          Toggle(isOn: $viewModel.saveImages) { Text("Images", tableName: "StorageSettings") }
          Toggle(isOn: $viewModel.saveText) { Text("Text", tableName: "StorageSettings") }
        } header: {
          Text(settingsLabel("Save", table: "StorageSettings"))
        } footer: {
          Text("SaveDescription", tableName: "StorageSettings")
            .settingsFootnote()
        }

        Section {
          LabeledContent {
            HStack {
              Text(storageSize)
                .foregroundStyle(.secondary)
                .help(Text("CurrentSizeTooltip", tableName: "StorageSettings"))
                .onAppear {
                  storageSize = Storage.shared.size
                }
              TextField("", value: $size, formatter: sizeFormatter)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .help(Text("SizeTooltip", tableName: "StorageSettings"))
              Stepper("", value: $size, in: 1...999)
                .labelsHidden()
            }
          } label: {
            Text(settingsLabel("Size", table: "StorageSettings"))
          }

          Picker(selection: $sortBy) {
            ForEach(Sorter.By.allCases) { mode in
              Text(mode.description)
            }
          } label: {
            Text(settingsLabel("SortBy", table: "StorageSettings"))
          }
          .help(Text("SortByTooltip", tableName: "StorageSettings"))
        }

        Section {
          Picker(selection: $retention) {
            ForEach(HistoryRetention.allCases) { retention in
              Text(retention.title).tag(retention)
            }
          } label: {
            Text("keep_history")
          }
          .onChange(of: retention) {
            AppState.shared.history.removeExpired()
          }
        } footer: {
          Text("keep_footer")
            .settingsFootnote()
        }
      }
      .formStyle(.grouped)
    }
  }
}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
