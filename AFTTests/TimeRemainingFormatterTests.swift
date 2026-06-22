import XCTest
@testable import AFT

final class TimeRemainingFormatterTests: XCTestCase {
    func testUnknown() {
        XCTAssertEqual(TimeRemainingFormatter.string(nil), "Estimating time remaining…")
    }
    func testLessThan5() {
        XCTAssertEqual(TimeRemainingFormatter.string(3), "Less than 5 seconds remaining")
    }
    func testLessThan15() {
        XCTAssertEqual(TimeRemainingFormatter.string(12), "Less than 15 seconds remaining")
    }
    func testAboutOneMinute() {
        XCTAssertEqual(TimeRemainingFormatter.string(58), "About 1 minute remaining")
    }
    func testAboutMinutes() {
        XCTAssertEqual(TimeRemainingFormatter.string(200), "About 3 minutes remaining")
    }
    func testAboutHours() {
        XCTAssertEqual(TimeRemainingFormatter.string(7200), "About 2 hours remaining")
    }
}
