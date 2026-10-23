import SwiftUI

struct ConfirmationView<Content: View>: View {
  @Bindable var item: FooterItem
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .onTapGesture { item.perform() }
      .modifier(ConfirmationModifier(item: item))
  }
}

struct ConfirmationModifier: ViewModifier {
  @Bindable var item: FooterItem

  func body(content: Content) -> some View {
    if let confirmation = item.confirmation, let suppressConfirmation = item.suppressConfirmation {
      content
        .confirmationDialog(confirmation.message, isPresented: $item.showConfirmation) {
          Text(confirmation.comment)
          Button(confirmation.confirm, role: .destructive) {
            item.action()
          }
          Button(confirmation.cancel, role: .cancel) {}
        }
        .dialogSuppressionToggle(isSuppressed: suppressConfirmation)
    } else {
      content
    }
  }
}
