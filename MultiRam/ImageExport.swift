import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// Writes clipboard images to read-only files that other apps can open, keeping the original bytes.
enum ImageExport {
  struct Representation: Equatable {
    let data: Data
    let type: UTType
  }

  // Original or lossless formats first. TIFF is last: pasteboard TIFFs are large and often hold
  // several resolutions of the same picture.
  static let preferredTypes: [UTType] = [.png, .jpeg, .heic, .heif, .gif, .webP, .tiff]

  static var defaultDirectory: URL {
    temporaryDirectory().appendingPathComponent("OpenWith", isDirectory: true)
  }

  static func bestRepresentation(from contents: [(type: String, data: Data?)]) -> Representation? {
    let candidates = contents.compactMap { content -> Representation? in
      guard let declared = UTType(content.type), declared.conforms(to: .image),
            let data = content.data, !data.isEmpty,
            let sniffed = sniffedType(of: data) else {
        return nil
      }
      // Trust the bytes over the pasteboard label.
      return Representation(data: data, type: sniffed)
    }
    for type in preferredTypes {
      if let match = candidates.first(where: { $0.type == type }) {
        return match
      }
    }
    return candidates.first
  }

  @MainActor
  static func representation(of item: HistoryItem) -> Representation? {
    // After a delete is saved, isDeleted is false again but the model has no context.
    guard item.modelContext != nil, !item.isDeleted else { return nil }
    let contents = item.contents.map { (type: $0.type, data: $0.value) }
    if let best = bestRepresentation(from: contents) {
      return best
    }
    // Universal Clipboard images arrive as a file URL pointing to a JPEG.
    if let data = item.imageData, let type = sniffedType(of: data) {
      return Representation(data: data, type: type)
    }
    return nil
  }

  static func sniffedType(of data: Data) -> UTType? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let identifier = CGImageSourceGetType(source) else {
      return nil
    }
    return UTType(identifier as String)
  }

  // The type the file will have after export, without converting anything.
  static func exportedType(of representation: Representation) -> UTType {
    if representation.type == .tiff, losslessPNGSource(fromTIFF: representation.data) != nil {
      return .png
    }
    return representation.type
  }

  // TIFF becomes PNG when that keeps every pixel; all other formats keep their original bytes.
  static func exportable(_ representation: Representation) -> Representation {
    guard representation.type == .tiff,
          let (source, index) = losslessPNGSource(fromTIFF: representation.data) else {
      return representation
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
      return representation
    }
    CGImageDestinationAddImageFromSource(destination, source, index, nil)
    guard CGImageDestinationFinalize(destination) else {
      return representation
    }
    return Representation(data: output as Data, type: .png)
  }

  // Only RGB or gray images with integer samples up to 16 bits convert to PNG without loss.
  // CMYK, Lab and floating point TIFFs from design apps stay TIFF.
  private static func losslessPNGSource(fromTIFF data: Data) -> (CGImageSource, Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let count = CGImageSourceGetCount(source)
    guard count > 0 else { return nil }

    var bestIndex = 0
    var bestArea = 0
    for index in 0..<count {
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
      let model = properties[kCGImagePropertyColorModel] as? String
      guard model == (kCGImagePropertyColorModelRGB as String) || model == (kCGImagePropertyColorModelGray as String),
            (properties[kCGImagePropertyDepth] as? Int ?? 8) <= 16,
            (properties[kCGImagePropertyIsFloat] as? Bool) != true else {
        return nil
      }
      let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
      let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
      let area = width * height
      if area > bestArea {
        bestArea = area
        bestIndex = index
      }
    }
    return (source, bestIndex)
  }

  // Each image gets its own folder named by its content hash, so a repeated export reuses the file.
  static func write(_ representation: Representation, name: String, in directory: URL) throws -> URL {
    let digest = SHA256.hash(data: representation.data).prefix(8).map { String(format: "%02x", $0) }.joined()
    var folder = directory.appendingPathComponent(digest, isDirectory: true)
    let fileExtension = representation.type.preferredFilenameExtension ?? "image"
    let fileName = sanitized(name) + "." + fileExtension
    var file = folder.appendingPathComponent(fileName)
    let fileManager = FileManager.default

    if fileManager.fileExists(atPath: file.path) {
      if isUntouchedCopy(file, of: representation.data) {
        // Keep a reused copy from being purged while an app may still have it open.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: folder.path)
        return file
      }
      // The user unlocked and edited this copy in another app: leave it alone and export afresh.
      folder = directory.appendingPathComponent("\(digest)-\(UUID().uuidString.prefix(8))", isDirectory: true)
      file = folder.appendingPathComponent(fileName)
    }

    try fileManager.createDirectory(
      at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
    )
    try representation.data.write(to: file, options: .atomic)
    // Read-only, so Save in an editor asks for a new location instead of writing into a temporary folder.
    try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
    return file
  }

  private static func isUntouchedCopy(_ file: URL, of data: Data) -> Bool {
    let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]) as? Int
    guard permissions == 0o444 else { return false }
    return (try? Data(contentsOf: file)) == data
  }

  // A copy that became writable was unlocked in an editor, which may have saved changes into it.
  private static func containsEditedCopy(_ folder: URL) -> Bool {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    return files.contains { name in
      let path = folder.appendingPathComponent(name).path
      let permissions = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? Int ?? 0
      return permissions & 0o222 != 0
    }
  }

  static func removeAll(in directory: URL) {
    try? FileManager.default.removeItem(at: directory)
  }

  // Removes exported copies that have not been used for a while. Apps load images when they open
  // them, so a day is far longer than any app needs the file.
  static func purge(_ directory: URL, olderThan age: TimeInterval, now: Date = Date()) {
    let fileManager = FileManager.default
    guard let folders = try? fileManager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
    ) else {
      return
    }
    for folder in folders {
      let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      // Copies the user edited stay; the system cleans its temporary folder after a few days.
      if now.timeIntervalSince(modified ?? .distantPast) > age, !containsEditedCopy(folder) {
        try? fileManager.removeItem(at: folder)
      }
    }
  }

  static func fileName(for item: HistoryItem) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    return "MultiRam \(formatter.string(from: item.firstCopiedAt))"
  }

  private static func sanitized(_ name: String) -> String {
    let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    return cleaned.isEmpty ? "MultiRam" : cleaned
  }

  // The copy goes to the app's Darwin temporary folder, /var/folders/…/T/<bundle id>. It is outside the
  // sandbox container, so other apps open it without macOS asking for access to another app's data,
  // and the sandbox lets MultiRam hand sandboxed apps such as Preview access to it.
  // Inside the sandbox the temporary folder setting points into the container, while the cache
  // folder names the per-app folder; the temporary folder is its "T" sibling.
  private static func temporaryDirectory() -> URL {
    if let cache = darwinDirectory(_CS_DARWIN_USER_CACHE_DIR) {
      let appFolder = cache.lastPathComponent
      let cacheRoot = cache.deletingLastPathComponent()
      if cacheRoot.lastPathComponent == "C" {
        return cacheRoot.deletingLastPathComponent()
          .appendingPathComponent("T", isDirectory: true)
          .appendingPathComponent(appFolder, isDirectory: true)
      }
    }
    return darwinDirectory(_CS_DARWIN_USER_TEMP_DIR) ?? FileManager.default.temporaryDirectory
  }

  private static func darwinDirectory(_ name: Int32) -> URL? {
    let length = confstr(name, nil, 0)
    guard length > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: length)
    guard confstr(name, &buffer, length) > 0 else { return nil }
    return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
  }
}
