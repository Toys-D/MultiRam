import SwiftUI
import Defaults

struct IgnoreRegexpsSettingsView: View {
  @Default(.ignoreRegexp) private var ignoredRegexps

  @FocusState private var focus: String.ID?
  @State private var edits: [String: String] = [:]
  @State private var selection = ""

  var body: some View {
    VStack(alignment: .leading) {
      List(selection: $selection) {
        ForEach(ignoredRegexps) { regexp in
          TextField("", text: Binding(
            get: { edits[regexp] ?? regexp },
            set: { edits[regexp] = $0 })
          ).onSubmit {
            let value = edits[regexp] ?? regexp
            guard !value.isEmpty,
                  (try? NSRegularExpression(pattern: value)) != nil,
                  let index = ignoredRegexps.firstIndex(of: regexp) else { return }
            guard value == regexp || !ignoredRegexps.contains(value) else { return }
            ignoredRegexps[index] = value
            edits.removeValue(forKey: regexp)
            selection = value
            focus = value
          }.focused($focus, equals: regexp)
        }
      }.onDeleteCommand {
        remove(selection)
      }

      ControlGroup {
        Button("", systemImage: "plus") {
          let value = "^[a-zA-Z0-9]{50}$"
          if !ignoredRegexps.contains(value) { ignoredRegexps.append(value) }
          focus = value
        }
        Button("", systemImage: "minus") {
          remove(selection)
        }
      }.frame(width: 50)

      if ignoredRegexps.contains(where: {
        let value = edits[$0] ?? $0
        return value.isEmpty || (try? NSRegularExpression(pattern: value)) == nil
      }) {
        Text("InvalidRegularExpression")
          .foregroundStyle(.red)
          .controlSize(.small)
      }

      Text("IgnoredRegexpsDescription", tableName: "IgnoreSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
    }.padding()
  }

  private func remove(_ regexp: String?) {
    guard let regexp else { return }

    ignoredRegexps.removeAll(where: { $0 == regexp })
    edits.removeValue(forKey: regexp)
  }
}

#Preview {
  IgnoreRegexpsSettingsView()
    .environment(\.locale, .init(identifier: "en"))
}
