import SwiftUI

enum About {
  static let appName = "MultiRam History"
  static let developer = "Dmitry Kohan"
  static let tagline = "3D Design. Engineer – developer."
  static let studio = "Pixmap Labs"
  static let email = "pixmap1981@gmail.com"
  static let repository = "Toys-D/MultiRam"

  static let repositoryURL = URL(string: "https://github.com/\(repository)")!
  static let licenseURL = URL(string: "https://github.com/\(repository)/blob/master/LICENSE")!
  static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
  static let emailURL = URL(string: "mailto:\(email)")!
  static let paypalURL = URL(
    string: "https://www.paypal.com/cgi-bin/webscr?cmd=_xclick&business=pixmap1981%40gmail.com"
      + "&item_name=MultiRam+History&currency_code=USD"
  )!

  static var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return String(
      format: NSLocalizedString("about_version", comment: ""),
      info["CFBundleShortVersionString"] as? String ?? "",
      info["CFBundleVersion"] as? String ?? ""
    )
  }
}

struct AboutSettingsPane: View {
  var body: some View {
    SettingsPage(title: SettingsSection.about.title) {
      Form {
        Section {
          HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
              .resizable()
              .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
              Text(About.appName)
                .font(.system(size: 22, weight: .bold))
              Text(About.version)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
          .padding(.vertical, 4)
        }

        Section {
          LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
              Text(About.developer)
              Text(About.tagline)
                .font(.caption)
            }
          } label: {
            Text("about_developer")
          }
          LabeledContent {
            Text(About.studio)
          } label: {
            Text("about_company")
          }
          LabeledContent {
            Link(NSLocalizedString("about_license_value", comment: ""), destination: About.licenseURL)
          } label: {
            Text("about_license")
          }
          LabeledContent {
            Link(destination: About.repositoryURL) {
              Label(About.repository, systemImage: "chevron.left.forwardslash.chevron.right")
            }
          } label: {
            Text("about_repository")
          }
          LabeledContent {
            Link(About.email, destination: About.emailURL)
          } label: {
            Text("about_contact")
          }
          LabeledContent {
            Link(destination: About.releasesURL) {
              Text("about_all_releases")
            }
          } label: {
            Text("about_releases")
          }
        }

        Section {
          VStack(alignment: .leading, spacing: 10) {
            Text("support_title")
              .font(.headline)
            Text("support_text")
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Link(destination: About.paypalURL) {
              Label("support_button", systemImage: "heart.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(SettingsTheme.selectedText)
                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("support-paypal")
            Text("support_thanks")
            Text("support_note")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
        }
      }
      .formStyle(.grouped)
    }
  }
}
