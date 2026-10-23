import Cocoa

class About {
  static let developer = "Dmitry Kohan"
  static let studio = "Pixmap Labs"
  static let email = "pixmap1981@gmail.com"
  static let profile = "github.com/Toys-D"

  static var creditsText: String {
    """
    MultiRam History

    \(developer)
    \(studio)
    3D Design. Engineer – developer.
    \(email)
    \(profile)
    """
  }

  private var credits: NSMutableAttributedString {
    let credits = NSMutableAttributedString(
      string: Self.creditsText,
      attributes: [.foregroundColor: NSColor.labelColor]
    )
    let text = credits.string as NSString
    credits.addAttribute(.link, value: "mailto:\(Self.email)", range: text.range(of: Self.email))
    credits.addAttribute(.link, value: "https://\(Self.profile)", range: text.range(of: Self.profile))
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }

  @objc
  func openAbout(_ sender: NSMenuItem?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
