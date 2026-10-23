import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MultiRam

final class ImageExportTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ImageExportTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testPrefersPNGOverTIFF() {
    let representation = ImageExport.bestRepresentation(from: [
      (NSPasteboard.PasteboardType.tiff.rawValue, imageData(.tiff, width: 10, height: 10)),
      (NSPasteboard.PasteboardType.png.rawValue, imageData(.png, width: 10, height: 10))
    ])
    XCTAssertEqual(representation?.type, .png)
  }

  func testPrefersJPEGOverTIFF() {
    let representation = ImageExport.bestRepresentation(from: [
      (NSPasteboard.PasteboardType.tiff.rawValue, imageData(.tiff, width: 10, height: 10)),
      ("public.jpeg", imageData(.jpeg, width: 10, height: 10))
    ])
    XCTAssertEqual(representation?.type, .jpeg)
  }

  func testIgnoresContentsThatAreNotImages() {
    let representation = ImageExport.bestRepresentation(from: [
      (NSPasteboard.PasteboardType.string.rawValue, Data("hello".utf8)),
      (NSPasteboard.PasteboardType.png.rawValue, nil)
    ])
    XCTAssertNil(representation)
  }

  func testUsesTheRealFormatWhenTheLabelIsWrong() {
    let representation = ImageExport.bestRepresentation(from: [
      (NSPasteboard.PasteboardType.tiff.rawValue, imageData(.png, width: 10, height: 10))
    ])
    XCTAssertEqual(representation?.type, .png)
  }

  func testConvertsRGBTIFFToPNGFromTheLargestImage() throws {
    let tiff = try XCTUnwrap(NSBitmapImageRep.tiffRepresentationOfImageReps(
      in: [bitmap(width: 40, height: 20), bitmap(width: 80, height: 40)], using: .none, factor: 0
    ))
    let exported = ImageExport.exportable(ImageExport.Representation(data: tiff, type: .tiff))
    XCTAssertEqual(exported.type, .png)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(exported.data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(image.width, 80)
    XCTAssertEqual(image.height, 40)
  }

  func testKeepsCMYKTIFFUnchanged() throws {
    let tiff = try XCTUnwrap(bitmap(width: 16, height: 16, cmyk: true).tiffRepresentation)
    let exported = ImageExport.exportable(ImageExport.Representation(data: tiff, type: .tiff))
    XCTAssertEqual(exported.type, .tiff)
    XCTAssertEqual(exported.data, tiff)
  }

  func testKeepsJPEGBytesUnchanged() {
    let jpeg = imageData(.jpeg, width: 20, height: 10)
    let exported = ImageExport.exportable(ImageExport.Representation(data: jpeg, type: .jpeg))
    XCTAssertEqual(exported.type, .jpeg)
    XCTAssertEqual(exported.data, jpeg)
  }

  func testWritesAReadOnlyCopyWithTheRightExtension() throws {
    let png = imageData(.png, width: 12, height: 12)
    let url = try ImageExport.write(ImageExport.Representation(data: png, type: .png), name: "Shot", in: directory)
    XCTAssertEqual(url.pathExtension, "png")
    XCTAssertEqual(url.deletingPathExtension().lastPathComponent, "Shot")
    XCTAssertEqual(try Data(contentsOf: url), png)
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    XCTAssertEqual(permissions, 0o444)
  }

  func testWritingTheSameImageAgainReusesTheCopy() throws {
    let representation = ImageExport.Representation(data: imageData(.png, width: 12, height: 12), type: .png)
    let first = try ImageExport.write(representation, name: "Shot", in: directory)
    let second = try ImageExport.write(representation, name: "Shot", in: directory)
    XCTAssertEqual(first, second)
  }

  func testPurgeRemovesOnlyOldCopies() throws {
    let old = try ImageExport.write(
      ImageExport.Representation(data: imageData(.png, width: 4, height: 4), type: .png), name: "Old", in: directory
    )
    let fresh = try ImageExport.write(
      ImageExport.Representation(data: imageData(.png, width: 5, height: 5), type: .png), name: "Fresh", in: directory
    )
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -2 * 86_400)],
      ofItemAtPath: old.deletingLastPathComponent().path
    )

    ImageExport.purge(directory, olderThan: 86_400, now: Date())

    XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
  }

  func testReuseSkipsACopyTheUserUnlockedAndEdited() throws {
    let representation = ImageExport.Representation(data: imageData(.png, width: 9, height: 9), type: .png)
    let first = try ImageExport.write(representation, name: "Shot", in: directory)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: first.path)
    try Data("edited".utf8).write(to: first)

    let second = try ImageExport.write(representation, name: "Shot", in: directory)

    XCTAssertNotEqual(first, second)
    XCTAssertEqual(try Data(contentsOf: second), representation.data)
    XCTAssertEqual(try Data(contentsOf: first), Data("edited".utf8))
  }

  func testPurgeKeepsACopyTheUserEdited() throws {
    let copy = try ImageExport.write(
      ImageExport.Representation(data: imageData(.png, width: 7, height: 7), type: .png), name: "Edited", in: directory
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: copy.path)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -2 * 86_400)],
      ofItemAtPath: copy.deletingLastPathComponent().path
    )

    ImageExport.purge(directory, olderThan: 86_400, now: Date())

    XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
  }

  func testRemoveAllDeletesEveryCopy() throws {
    _ = try ImageExport.write(
      ImageExport.Representation(data: imageData(.png, width: 4, height: 4), type: .png), name: "One", in: directory
    )
    _ = try ImageExport.write(
      ImageExport.Representation(data: imageData(.png, width: 5, height: 5), type: .png), name: "Two", in: directory
    )
    ImageExport.removeAll(in: directory)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }

  @MainActor
  func testSavedDeletionIsNotExported() throws {
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.png.rawValue, value: imageData(.png, width: 6, height: 6))
    ]
    try Storage.shared.context.save()
    XCTAssertNotNil(ImageExport.representation(of: item))

    Storage.shared.context.delete(item)
    try Storage.shared.context.save()

    XCTAssertNil(ImageExport.representation(of: item))
  }

  func testDefaultDirectoryIsOutsideTheAppContainer() {
    // Other apps open the copy from here without the macOS prompt about another app's data.
    let path = ImageExport.defaultDirectory.path
    XCTAssertFalse(path.contains("/Library/Containers/"), path)
    XCTAssertTrue(path.hasSuffix("/OpenWith"), path)
  }

  func testDefaultDirectoryIsWritableFromTheSandbox() throws {
    let folder = ImageExport.defaultDirectory.appendingPathComponent("test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try ImageExport.write(
      ImageExport.Representation(data: imageData(.png, width: 3, height: 3), type: .png), name: "Probe", in: folder
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }

  func testFileNameUsesTheCopyDate() throws {
    let item = HistoryItem()
    var components = DateComponents()
    components.year = 2026; components.month = 10; components.day = 22
    components.hour = 16; components.minute = 5; components.second = 9
    item.firstCopiedAt = try XCTUnwrap(Calendar.current.date(from: components))
    XCTAssertEqual(ImageExport.fileName(for: item), "MultiRam 2026-10-22 16.05.09")
  }

  private func bitmap(width: Int, height: Int, cmyk: Bool = false) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: !cmyk, isPlanar: false,
      colorSpaceName: cmyk ? .deviceCMYK : .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    if let data = rep.bitmapData {
      for index in 0..<(rep.bytesPerRow * height) {
        data[index] = UInt8(truncatingIfNeeded: index * 7)
      }
    }
    return rep
  }

  private func imageData(_ type: UTType, width: Int, height: Int) -> Data {
    let rep = bitmap(width: width, height: height)
    switch type {
    case .png: return rep.representation(using: .png, properties: [:])!
    case .jpeg: return rep.representation(using: .jpeg, properties: [:])!
    default: return rep.tiffRepresentation!
    }
  }
}
