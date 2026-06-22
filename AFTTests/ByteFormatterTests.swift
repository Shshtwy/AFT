import XCTest
@testable import AFT

final class ByteFormatterTests: XCTestCase {
    func testKilobytes() {
        // ByteCountFormatter(.file) is the source of truth for formatting.
        let expected = ByteCountFormatter.string(fromByteCount: 307200, countStyle: .file)
        XCTAssertEqual(AFTByteFormatter.string(307200), expected)
    }
    func testGigabytesAvailable() {
        XCTAssertTrue(AFTByteFormatter.string(112_430_000_000).hasSuffix("GB"))
    }
    func testFolderDisplayIsDash() {
        let folder = MTPEntry(id: 1, storageId: 1, parentId: 0, name: "DCIM",
                              isFolder: true, size: 0, modified: nil)
        XCTAssertEqual(AFTByteFormatter.sizeColumn(folder), "--")
    }
}
