import SwiftUI
import UniformTypeIdentifiers

// Buttons under an image in the side panel that open a copy of it in another application.
struct OpenWithBar: View {
  let item: HistoryItemDecorator

  @Environment(AppState.self) private var appState
  @State private var applications = OpenWithApplications()

  private static let visibleCount = 4
  private static let iconSize: CGFloat = 26

  var body: some View {
    // The side panel can be narrower than the full bar when the list takes most of the screen.
    // Then fewer icons are shown and the rest move into the More menu, which always stays visible.
    ViewThatFits(in: .horizontal) {
      ForEach((0...Self.visibleCount).reversed(), id: \.self) { count in
        bar(showing: count)
      }
    }
    .padding(.horizontal, Popup.detailPadding)
    .frame(maxWidth: .infinity)
    .frame(height: Popup.detailActionBarHeight - 1)
    .clipped()
    .task(id: item.id) {
      guard let representation = ImageExport.representation(of: item.item) else { return }
      applications = ImageEditorCatalog.shared.applications(for: ImageExport.exportedType(of: representation))
    }
  }

  private func bar(showing count: Int) -> some View {
    HStack(spacing: 8) {
      ForEach(applications.featured.prefix(count)) { application in
        Button {
          perform { try await OpenWithController.shared.open(item, with: application) }
        } label: {
          Image(nsImage: ApplicationIconCache.shared.icon(for: application.url))
            .resizable()
            .frame(width: Self.iconSize, height: Self.iconSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Self.openTitle(application))
        .accessibilityLabel(Self.openTitle(application))
        .accessibilityIdentifier("open-with-app")
      }

      Spacer(minLength: 0)

      Menu {
        menuContent(hiding: count)
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help(Text("open_with_more"))
      .accessibilityLabel(Text("open_with_more"))
      .accessibilityIdentifier("open-with-more")
    }
  }

  @ViewBuilder
  private func menuContent(hiding visibleCount: Int) -> some View {
    let remaining = Array(applications.featured.dropFirst(visibleCount))
    ForEach(remaining) { application in
      applicationButton(application)
    }
    if !remaining.isEmpty {
      Divider()
    }
    if !applications.all.isEmpty {
      Menu {
        ForEach(applications.all) { application in
          applicationButton(application)
        }
      } label: {
        Text("open_with_all_apps")
      }
    }
    Button {
      perform { try await OpenWithController.shared.chooseApplication(for: item) }
    } label: {
      Text("open_with_other_app")
    }
    Divider()
    Button {
      perform { try await OpenWithController.shared.revealInFinder(item) }
    } label: {
      Text("open_with_show_in_finder")
    }
  }

  private func applicationButton(_ application: OpenWithApplication) -> some View {
    Button {
      perform { try await OpenWithController.shared.open(item, with: application) }
    } label: {
      Label {
        Text(verbatim: application.name)
      } icon: {
        Image(nsImage: ApplicationIconCache.shared.icon(for: application.url, size: 16))
      }
    }
  }

  // The popup floats above other windows, so it closes before the other application comes forward.
  private func perform(_ action: @escaping @MainActor () async throws -> Void) {
    appState.popup.close()
    Task { @MainActor in
      do {
        try await action()
      } catch {
        OpenWithController.present(error)
      }
    }
  }

  private static func openTitle(_ application: OpenWithApplication) -> Text {
    Text(verbatim: String(format: NSLocalizedString("open_in_app", comment: ""), application.name))
  }
}

// Application icons by path and size, shared by every image in the session.
final class ApplicationIconCache {
  static let shared = ApplicationIconCache()

  private var cache: [String: NSImage] = [:]

  func icon(for url: URL, size: CGFloat = 32) -> NSImage {
    let key = "\(url.path)#\(size)"
    if let icon = cache[key] {
      return icon
    }
    let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage ?? NSImage()
    icon.size = NSSize(width: size, height: size)
    cache[key] = icon
    return icon
  }
}
