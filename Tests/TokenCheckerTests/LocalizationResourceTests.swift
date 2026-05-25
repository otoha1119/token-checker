import Foundation
import XCTest

final class LocalizationResourceTests: XCTestCase {
    func testEnglishAndChineseLocalizationsHaveSameKeys() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let english = root.appending(path: "Resources/en.lproj/Localizable.strings")
        let chinese = root.appending(path: "Resources/zh-Hans.lproj/Localizable.strings")

        let englishKeys = try localizationKeys(at: english)
        let chineseKeys = try localizationKeys(at: chinese)

        XCTAssertFalse(englishKeys.isEmpty, "English localization must not be empty")
        XCTAssertEqual(englishKeys, chineseKeys, "English and Simplified Chinese localization keys must match")
    }

    private func localizationKeys(at url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        return Set((plist ?? [:]).keys)
    }
}
