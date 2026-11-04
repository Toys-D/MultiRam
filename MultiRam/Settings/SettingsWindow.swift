import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
  case general, shortcuts, historyWindow, menuBar, storage, pins, ignore, privacy, about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return NSLocalizedString("Title", tableName: "GeneralSettings", comment: "")
    case .shortcuts: return NSLocalizedString("settings_shortcuts", comment: "")
    case .historyWindow: return NSLocalizedString("settings_history_window", comment: "")
    case .menuBar: return NSLocalizedString("settings_menu_bar", comment: "")
    case .storage: return NSLocalizedString("Title", tableName: "StorageSettings", comment: "")
    case .pins: return NSLocalizedString("Title", tableName: "PinsSettings", comment: "")
    case .ignore: return NSLocalizedString("Title", tableName: "IgnoreSettings", comment: "")
    case .privacy: return NSLocalizedString("settings_privacy", comment: "")
    case .about: return NSLocalizedString("settings_about", comment: "")
    }
  }

  var symbol: String {
    switch self {
    case .general: return "gearshape"
    case .shortcuts: return "keyboard"
    case .historyWindow: return "macwindow"
    case .menuBar: return "menubar.rectangle"
    case .storage: return "externaldrive"
    case .pins: return "pin"
    case .ignore: return "nosign"
    case .privacy: return "hand.raised"
    case .about: return "info.circle"
    }
  }

  // Labels shown on the page, so a search finds the section that holds a setting.
  private var labels: [(key: String, table: String?)] {
    switch self {
    case .general:
      return [("LaunchAtLogin", "GeneralSettings"), ("PasteAutomatically", "GeneralSettings"),
              ("PasteWithoutFormatting", "GeneralSettings"), ("Search", "GeneralSettings"),
              ("NotificationsAndSounds", "GeneralSettings"), ("paste_access_title", nil)]
    case .shortcuts:
      return [("Open", "GeneralSettings"), ("OpenFallback", "GeneralSettings"),
              ("Pin", "GeneralSettings"), ("Delete", "GeneralSettings")]
    case .historyWindow:
      return [("PopupAt", "AppearanceSettings"), ("PinTo", "AppearanceSettings"),
              ("ImageHeight", "AppearanceSettings"), ("HighlightMatches", "AppearanceSettings"),
              ("ShowSearchField", "AppearanceSettings"), ("ShowTitleBeforeSearchField", "AppearanceSettings"),
              ("ShowApplicationIcons", "AppearanceSettings"), ("ShowSpecialSymbols", "AppearanceSettings")]
    case .menuBar:
      return [("ShowMenuIcon", "AppearanceSettings"), ("ShowRecentCopyInMenuBar", "AppearanceSettings")]
    case .storage:
      return [("Save", "StorageSettings"), ("Files", "StorageSettings"), ("Images", "StorageSettings"),
              ("Text", "StorageSettings"), ("Size", "StorageSettings"), ("SortBy", "StorageSettings")]
    case .pins:
      return [("Key", "PinsSettings"), ("Alias", "PinsSettings"), ("Content", "PinsSettings")]
    case .ignore:
      return [("ApplicationsTab", "IgnoreSettings"), ("PasteboardTypesTab", "IgnoreSettings"),
              ("RegexpTab", "IgnoreSettings")]
    case .privacy:
      return [("TurnOff", "AdvancedSettings"), ("ClearHistoryOnQuit", "AdvancedSettings"),
              ("ClearSystemClipboard", "AdvancedSettings")]
    case .about:
      return [("about_developer", nil), ("about_company", nil), ("about_license", nil),
              ("about_repository", nil), ("about_contact", nil), ("about_releases", nil)]
    }
  }

  func matches(_ query: String) -> Bool {
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return true }
    let texts = [title] + labels.map { NSLocalizedString($0.key, tableName: $0.table, comment: "") }
    return texts.contains { $0.localizedCaseInsensitiveContains(query) }
  }
}

@Observable
final class SettingsModel {
  var selection: SettingsSection = .general
  var query = "" {
    didSet {
      if !visibleSections.contains(selection), let first = visibleSections.first {
        selection = first
      }
    }
  }

  var visibleSections: [SettingsSection] {
    SettingsSection.allCases.filter { $0.matches(query) }
  }
}

struct SettingsView: View {
  @Bindable var model: SettingsModel

  var body: some View {
    HStack(spacing: 0) {
      SettingsSidebar(model: model)
        .frame(width: 230)
      Divider()
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .tint(SettingsTheme.accent)
    .toggleStyle(.switch)
    .ignoresSafeArea()
    .frame(minWidth: 760, minHeight: 520)
  }

  @ViewBuilder
  private var detail: some View {
    switch model.selection {
    case .general: GeneralSettingsPane()
    case .shortcuts: ShortcutsSettingsPane()
    case .historyWindow: HistoryWindowSettingsPane()
    case .menuBar: MenuBarSettingsPane()
    case .storage: StorageSettingsPane()
    case .pins: PinsSettingsPane()
    case .ignore: IgnoreSettingsPane()
    case .privacy: AdvancedSettingsPane()
    case .about: AboutSettingsPane()
    }
  }
}

private struct SettingsSidebar: View {
  @Bindable var model: SettingsModel
  @FocusState private var listFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("", text: $model.query, prompt: Text("settings_search"))
          .textFieldStyle(.plain)
        if !model.query.isEmpty {
          Button {
            model.query = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 6)
      .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(model.visibleSections) { section in
            row(section)
          }
        }
      }
      .focusable()
      .focused($listFocused)
      .focusEffectDisabled()
      .onKeyPress(.downArrow) { move(by: 1) }
      .onKeyPress(.upArrow) { move(by: -1) }
    }
    .padding(.horizontal, 12)
    .padding(.top, 44)
    .padding(.bottom, 12)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(SidebarMaterial())
  }

  private func row(_ section: SettingsSection) -> some View {
    let selected = section == model.selection
    return Button {
      model.selection = section
      listFocused = true
    } label: {
      HStack(spacing: 10) {
        Image(systemName: section.symbol)
          .frame(width: 20)
        Text(section.title)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
      .foregroundStyle(selected ? SettingsTheme.selectedText : Color.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(selected ? SettingsTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 8))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("settings-section-\(section.rawValue)")
  }

  private func move(by offset: Int) -> KeyPress.Result {
    let sections = model.visibleSections
    guard let index = sections.firstIndex(of: model.selection) else { return .ignored }
    let next = index + offset
    guard sections.indices.contains(next) else { return .handled }
    model.selection = sections[next]
    return .handled
  }
}

private struct SidebarMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .sidebar
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@MainActor
final class SettingsWindowPresenter {
  private let model = SettingsModel()
  private var window: NSWindow?

  func show(_ section: SettingsSection? = nil) {
    if let section {
      model.query = ""
      model.selection = section
    }
    let window = window ?? makeWindow()
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  private func makeWindow() -> NSWindow {
    let root = SettingsView(model: model)
      .environment(AppState.shared)
      .modelContainer(Storage.shared.container)
    let controller = NSHostingController(rootView: root)
    // The window keeps the size the user gives it instead of following the content.
    controller.sizingOptions = []

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 880, height: 640))
    window.contentMinSize = NSSize(width: 760, height: 520)
    window.title = NSLocalizedString("settings_window_title", comment: "")
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.identifier = NSUserInterfaceItemIdentifier("multiram-settings")
    window.center()
    window.setFrameAutosaveName("MultiRamSettings")
    return window
  }
}
