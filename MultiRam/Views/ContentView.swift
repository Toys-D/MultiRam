import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var appState = AppState.shared
  @State private var modifierFlags = ModifierFlags()
  @State private var scenePhase: ScenePhase = .background

  @FocusState private var searchFocused: Bool

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      HStack(spacing: 0) {
        if appState.popup.detailSide == .leading {
          detailColumn
        }

        KeyHandlingView(searchQuery: $appState.history.searchQuery, searchFocused: $searchFocused) {
          VStack(spacing: 0) {
            VStack(spacing: 0) {
              HeaderView(searchFocused: $searchFocused)

              VStack(alignment: .leading, spacing: 0) {
                HistoryListView(
                  searchQuery: $appState.history.searchQuery,
                  searchFocused: $searchFocused
                )
              }
              .animation(.default.speed(3), value: appState.history.items)
              .animation(
                .default.speed(3),
                value: appState.history.pasteStack?.id
              )
              .padding(.horizontal, Popup.horizontalPadding)
              .onAppear {
                searchFocused = true
              }
              .onMouseMove {
                appState.navigator.isKeyboardNavigating = false
              }
            }
            .frame(minHeight: 0)
            .layoutPriority(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if appState.popup.detailSide == .trailing {
          detailColumn
        }
      }
      .task {
        await appState.history.reload()
      }
    }
    .animation(.easeInOut(duration: 0.2), value: appState.searchVisible)
    .environment(appState)
    .environment(modifierFlags)
    .environment(\.scenePhase, scenePhase)
    .alert("HistoryStorageErrorTitle", isPresented: Binding(
      get: { appState.history.storageError != nil },
      set: { if !$0 { appState.history.storageError = nil } }
    )) {
      Button("OK") { appState.history.storageError = nil }
    } message: {
      Text(appState.history.storageError ?? "")
    }
    // FloatingPanel is not a scene, so let's implement custom scenePhase..
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .active
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .background
      }
    }
  }

  // The side panel with the full content of the item chosen with the row's expand button.
  @ViewBuilder
  private var detailColumn: some View {
    if let item = appState.popup.detailItem {
      Divider()
      HistoryItemDetailView(item: item)
        .id(item.id)
        .frame(width: appState.popup.detailWidth)
    }
  }
}

#Preview {
  ContentView()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
