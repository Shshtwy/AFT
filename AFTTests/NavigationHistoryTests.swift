import XCTest
@testable import AFT

final class NavigationHistoryTests: XCTestCase {
    func testPushAndBack() {
        var h = NavigationHistory(root: 0)
        h.push(5); h.push(7)
        XCTAssertEqual(h.current, 7)
        XCTAssertEqual(h.back(), 5)
        XCTAssertEqual(h.back(), 0)
        XCTAssertNil(h.back())
    }
    func testForward() {
        var h = NavigationHistory(root: 0)
        h.push(5); _ = h.back()
        XCTAssertEqual(h.forward(), 5)
        XCTAssertNil(h.forward())
    }
    func testPushTruncatesForward() {
        var h = NavigationHistory(root: 0)
        h.push(5); h.push(7); _ = h.back()   // current = 5
        h.push(9)                            // forward to 7 discarded
        XCTAssertNil(h.forward())
        XCTAssertEqual(h.current, 9)
    }
    func testCanGoFlags() {
        var h = NavigationHistory(root: 0)
        XCTAssertFalse(h.canGoBack); XCTAssertFalse(h.canGoForward)
        h.push(1)
        XCTAssertTrue(h.canGoBack)
    }
}
