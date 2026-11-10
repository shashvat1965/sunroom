import XCTest
@testable import SunroomCore

final class SmokeTests: XCTestCase {
    func testBuilds() {
        XCTAssertEqual(CanvasTransform.identity.zoom, 1)
    }
}
