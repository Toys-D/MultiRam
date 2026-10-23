import Defaults
import KeyboardShortcuts
import SwiftUI

struct ListHeaderView: View {
  @FocusState.Binding var searchFocused: Bool
  @Binding var searchQuery: String

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  @Default(.showTitle) private var showTitle

  var body: some View {
    HStack {
      if showTitle {
        Text("MultiRam")
          .foregroundStyle(.secondary)
          .padding(.leading, 5)
          .overlay { WindowDragHandle() }
      }

      SearchFieldView(placeholder: "search_placeholder", query: $searchQuery)
        .focused($searchFocused)
        .frame(maxWidth: .infinity)
        .onChange(of: scenePhase) {
          if scenePhase == .background && !searchQuery.isEmpty {
            searchQuery = ""
          }
        }
        // Only reliable way to disable the cursor. allowsHitTesting() does not work
        .offset(y: appState.searchVisible ? 0 : -Popup.itemHeight)
    }
  }
}

private struct WindowDragHandle: NSViewRepresentable {
  final class DragView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
      (window as? FloatingPanel<ContentView>)?.drag(with: event)
    }
  }

  func makeNSView(context: Context) -> DragView { DragView() }
  func updateNSView(_ nsView: DragView, context: Context) {}
}
