import Defaults
import XCTest
@testable import MultiRam

final class SoftwareUpdaterTests: XCTestCase {
  private let release = Data("""
    {"tag_name": "v1.5.0", "html_url": "https://github.com/Toys-D/MultiRam/releases/tag/v1.5.0",
     "draft": false, "prerelease": false}
    """.utf8)

  func testComparesVersionsNumerically() {
    XCTAssertTrue(ReleaseVersion.isNewer("v1.10.0", than: "1.9.3"))
    XCTAssertTrue(ReleaseVersion.isNewer("1.4.1", than: "1.4"))
    XCTAssertFalse(ReleaseVersion.isNewer("v1.4.0", than: "1.4.0"))
    XCTAssertFalse(ReleaseVersion.isNewer("1.3.9", than: "1.4.0"))
    XCTAssertFalse(ReleaseVersion.isNewer("latest", than: "1.4.0"))
  }

  func testReadsTheLatestRelease() throws {
    let info = try XCTUnwrap(SoftwareUpdater.parse(release))
    XCTAssertEqual(info.version, "1.5.0")
    XCTAssertEqual(info.pageURL.absoluteString, "https://github.com/Toys-D/MultiRam/releases/tag/v1.5.0")
  }

  func testIgnoresDraftsAndPrereleases() {
    let prerelease = Data("""
      {"tag_name": "v2.0.0", "html_url": "https://github.com/Toys-D/MultiRam/releases/tag/v2.0.0",
       "draft": false, "prerelease": true}
      """.utf8)
    XCTAssertNil(SoftwareUpdater.parse(prerelease))
    XCTAssertNil(SoftwareUpdater.parse(Data("{}".utf8)))
  }

  func testReportsANewerRelease() async {
    let updater = SoftwareUpdater(currentVersion: "1.4.0", fetch: { _ in self.release })
    let result = await updater.check()
    XCTAssertEqual(result, .available(ReleaseInfo(
      version: "1.5.0", pageURL: URL(string: "https://github.com/Toys-D/MultiRam/releases/tag/v1.5.0")!
    )))
  }

  func testReportsUpToDate() async {
    let updater = SoftwareUpdater(currentVersion: "1.5.0", fetch: { _ in self.release })
    let result = await updater.check()
    XCTAssertEqual(result, .upToDate("1.5.0"))
  }

  func testReportsAFailedRequest() async {
    let updater = SoftwareUpdater(currentVersion: "1.4.0", fetch: { _ in throw URLError(.notConnectedToInternet) })
    let result = await updater.check()
    XCTAssertEqual(result, .failed)
  }

  func testAutomaticChecksStaySilentForASkippedVersion() {
    let info = ReleaseInfo(version: "1.5.0", pageURL: URL(string: "https://github.com/Toys-D/MultiRam/releases")!)
    XCTAssertFalse(SoftwareUpdater.shouldAnnounce(.available(info), userInitiated: false, skippedVersion: "1.5.0"))
    XCTAssertTrue(SoftwareUpdater.shouldAnnounce(.available(info), userInitiated: true, skippedVersion: "1.5.0"))
    XCTAssertTrue(SoftwareUpdater.shouldAnnounce(.available(info), userInitiated: false, skippedVersion: nil))
    XCTAssertFalse(SoftwareUpdater.shouldAnnounce(.upToDate("1.5.0"), userInitiated: false, skippedVersion: nil))
    XCTAssertTrue(SoftwareUpdater.shouldAnnounce(.upToDate("1.5.0"), userInitiated: true, skippedVersion: nil))
    XCTAssertFalse(SoftwareUpdater.shouldAnnounce(.failed, userInitiated: false, skippedVersion: nil))
  }

  func testChecksAtMostOnceADay() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    XCTAssertTrue(SoftwareUpdater.isCheckDue(lastCheck: nil, now: now))
    XCTAssertFalse(SoftwareUpdater.isCheckDue(lastCheck: now.addingTimeInterval(-3_600), now: now))
    XCTAssertTrue(SoftwareUpdater.isCheckDue(lastCheck: now.addingTimeInterval(-25 * 3_600), now: now))
  }
}
