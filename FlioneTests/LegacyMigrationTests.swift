import XCTest
@testable import Flione

/// 改名（Finify → Flione）的設定鍵對應（D52）
final class LegacyMigrationTests: XCTestCase {
    func testRenamedKeys() {
        XCTAssertEqual(LegacyMigration.renamedKey("FinifyTheme"), "FlioneTheme")
        XCTAssertEqual(LegacyMigration.renamedKey("FinifyYouTubePlaysICloud"), "FlioneYouTubePlaysICloud")
        XCTAssertEqual(LegacyMigration.renamedKey("AppleLanguages"), "AppleLanguages")
        XCTAssertEqual(LegacyMigration.renamedKey("NSWindow Frame main"), "NSWindow Frame main")
    }

    @MainActor
    func testSettingsKeysUseNewPrefix() {
        XCTAssertTrue(SettingsKey.theme.hasPrefix("Flione"))
        XCTAssertTrue(LocalPlayCounts.syncKey.hasPrefix("Flione"))
    }
}
