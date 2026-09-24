import Foundation
import XCTest
@testable import BFFCore

/// The User-Agent's version is the app's: read from the bundle's Info.plist,
/// which `make release` stamps, so a release moves it with everything else.
final class UserAgentTests: XCTestCase {
    func testUserAgentCarriesTheAppsVersion() throws {
        let bundle = try appBundle(["CFBundleIdentifier": BFFAPI.appID,
                                    "CFBundleShortVersionString": "9.9",
                                    "CFBundleVersion": "123"])
        XCTAssertEqual(BFFAPI.userAgent(for: bundle), "menu-bar-frequencies-forever/9.9")
    }

    /// Outside the app — `swift test`, a bare `swift run` — the main bundle is
    /// some other program's, and its version is not ours to claim.
    func testAnotherBundlesVersionIsNotBorrowed() throws {
        let bundle = try appBundle(["CFBundleIdentifier": "com.example.host",
                                    "CFBundleShortVersionString": "7.7"])
        XCTAssertEqual(BFFAPI.userAgent(for: bundle), "menu-bar-frequencies-forever/dev")
    }

    /// The Info.plist `make release` stamps and build-app.sh copies into the
    /// app. The version is read back from the file rather than written here,
    /// so this follows every release instead of failing on each one — and it
    /// fails if the bundle identifier and `BFFAPI.appID` ever drift apart,
    /// which would otherwise send "dev" from the shipped app without a word.
    func testTheShippedInfoPlistNamesItsVersion() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/Info.plist")
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: source), format: nil)
                as? [String: Any])
        let version = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)

        XCTAssertEqual(BFFAPI.userAgent(for: try appBundle(info)),
                       "menu-bar-frequencies-forever/\(version)")
    }

    /// A real bundle on disk, `Probe.app/Contents/Info.plist`, in a directory
    /// of its own so `Bundle` has nothing cached for the path.
    private func appBundle(_ info: [String: Any]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-agent-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Probe.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: root.appendingPathComponent("Probe.app")))
    }
}
