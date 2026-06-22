import XCTest
@testable import AFT

final class StatusBarFormatterTests: XCTestCase {
    func testSelection() {
        let s = StatusBarFormatter.string(selected: 2, total: 17, freeBytes: 112_430_000_000)
        XCTAssertTrue(s.hasPrefix("2 of 17 selected, "))
        XCTAssertTrue(s.hasSuffix(" available"))
    }
    func testNoSelectionMultiple() {
        let s = StatusBarFormatter.string(selected: 0, total: 17, freeBytes: 112_430_000_000)
        XCTAssertTrue(s.hasPrefix("17 items, "))
    }
    func testNoSelectionSingle() {
        let s = StatusBarFormatter.string(selected: 0, total: 1, freeBytes: 1000)
        XCTAssertTrue(s.hasPrefix("1 item, "))
    }
}
