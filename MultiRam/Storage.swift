import Foundation
import SwiftData
import AppKit

@MainActor
class Storage {
  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    let files = [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
    let size = files.reduce(Int64(0)) { total, file in
      total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    guard size > 0 else { return "" }
    return ByteCountFormatter().string(fromByteCount: size)
  }

  private let url = URL.applicationSupportDirectory.appending(path: "MultiRam/Storage.sqlite")

  init() {
    var config = ModelConfiguration(url: url)

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      // Leave the existing database intact so it can be recovered.
      NSAlert(error: error).runModal()
      exit(EXIT_FAILURE)
    }
  }
}
