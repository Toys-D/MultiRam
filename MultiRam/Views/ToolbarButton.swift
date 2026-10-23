import SwiftUI

struct ToolbarButton<Label: View>: View {
  let action: @MainActor () -> Void
  let label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
    }
    .buttonStyle(.plain)
    .frame(minHeight: Popup.itemHeight)
  }
}
