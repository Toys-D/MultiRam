import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = Self("popup", default: Shortcut(.v, modifiers: [.option]))
  // Includes Control, so macOS delivers it even while a password field has focus,
  // when it withholds Option-only shortcuts such as the default above.
  static let popupFallback = Self("popupFallback", default: Shortcut(.v, modifiers: [.control, .option]))
  static let pin = Self("pin", default: Shortcut(.p, modifiers: [.option]))
  static let delete = Self("delete", default: Shortcut(.delete, modifiers: [.option]))
}
