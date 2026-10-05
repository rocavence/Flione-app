import XCTest
@testable import Flione

/// 新版通知（D53）：版本比較、GitHub release 解析、更新內容摘要
@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testVersionCompare() {
        XCTAssertTrue(UpdateChecker.isNewer("0.9.8", than: "0.9.7"))
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.7", than: "0.9.7"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.6", than: "0.9.7"))
    }

    func testParseRelease() throws {
        let json = """
        {"tag_name":"v0.9.8","html_url":"https://github.com/rocavence/Flione-app/releases/tag/v0.9.8","draft":false,"prerelease":false,
         "body":"## 新功能\\n\\n- **新版通知**：有新版時提示\\n- 第二點 `code`\\n- 第三點\\n- 第四點",
         "assets":[{"name":"Flione-0.9.8-AppleSilicon.dmg","browser_download_url":"https://example.com/a.dmg"},
                   {"name":"Flione-0.9.8-Intel.dmg","browser_download_url":"https://example.com/i.dmg"}]}
        """
        let release = try XCTUnwrap(UpdateChecker.parse(Data(json.utf8)))
        XCTAssertEqual(release.version, "0.9.8")
        #if arch(arm64)
        XCTAssertEqual(release.downloadURL?.absoluteString, "https://example.com/a.dmg")
        #else
        XCTAssertEqual(release.downloadURL?.absoluteString, "https://example.com/i.dmg")
        #endif
        XCTAssertEqual(release.notes, "• 新版通知：有新版時提示\n• 第二點 code\n• 第三點")
    }

    func testIgnoresPrerelease() {
        let json = #"{"tag_name":"v1.0.0","html_url":"https://example.com","prerelease":true,"assets":[]}"#
        XCTAssertNil(UpdateChecker.parse(Data(json.utf8)))
    }
}
