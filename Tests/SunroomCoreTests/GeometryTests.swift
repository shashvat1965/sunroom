import XCTest
@testable import SunroomCore

final class GeometryTests: XCTestCase {

    // MARK: Construction

    func testCornerInitializerAcceptsCornersInAnyOrder() {
        let forward = CanvasRect(corner: pt(0, 0), corner: pt(10, 30))
        let reversed = CanvasRect(corner: pt(10, 30), corner: pt(0, 0))
        let mixed = CanvasRect(corner: pt(10, 0), corner: pt(0, 30))

        assertRect(forward, rect(0, 0, 10, 30))
        assertRect(reversed, rect(0, 0, 10, 30))
        assertRect(mixed, rect(0, 0, 10, 30))
    }

    func testZeroRect() {
        XCTAssertEqual(CanvasRect.zero, rect(0, 0, 0, 0))
        XCTAssertTrue(CanvasRect.zero.isEmpty)
    }

    // MARK: Min / max / standardization

    func testMinMaxWithNegativeSize() {
        let value = CanvasRect(origin: pt(10, 20), size: sz(-4, -8))
        XCTAssertEqual(value.minX, 6)
        XCTAssertEqual(value.maxX, 10)
        XCTAssertEqual(value.minY, 12)
        XCTAssertEqual(value.maxY, 20)
        XCTAssertEqual(value.width, 4)
        XCTAssertEqual(value.height, 8)
    }

    func testStandardizedNormalizesNegativeSize() {
        let value = CanvasRect(origin: pt(10, 20), size: sz(-4, -8))
        assertRect(value.standardized, rect(6, 12, 4, 8))
        assertRect(value.standardized.standardized, rect(6, 12, 4, 8))
    }

    func testCenterUsesMinAndMax() {
        assertPoint(rect(10, 20, 100, 50).center, pt(60, 45))
        assertPoint(CanvasRect(origin: pt(10, 10), size: sz(-10, -10)).center, pt(5, 5))
    }

    func testAreaAndIsEmpty() {
        XCTAssertEqual(rect(0, 0, 10, 20).area, 200)
        XCTAssertEqual(rect(0, 0, -10, 20).area, 0, "A negative dimension makes the rect empty")
        XCTAssertTrue(rect(0, 0, 0, 20).isEmpty)
        XCTAssertTrue(rect(0, 0, 10, 0).isEmpty)
        XCTAssertTrue(rect(0, 0, -1, 10).isEmpty)
        XCTAssertFalse(rect(0, 0, 1, 1).isEmpty)
    }

    // MARK: Predicates

    func testContainsIncludesEdges() {
        let value = rect(0, 0, 100, 50)
        XCTAssertTrue(value.contains(pt(0, 0)))
        XCTAssertTrue(value.contains(pt(100, 50)))
        XCTAssertTrue(value.contains(pt(50, 25)))
        XCTAssertFalse(value.contains(pt(-0.001, 0)))
        XCTAssertFalse(value.contains(pt(0, 50.001)))
    }

    func testIntersectsAndEdgeTouching() {
        let value = rect(0, 0, 10, 10)
        XCTAssertTrue(value.intersects(rect(5, 5, 10, 10)))
        XCTAssertTrue(value.intersects(rect(-5, -5, 10, 10)))
        // Edge-touching counts as intersecting (the index and marquee rely on it).
        XCTAssertTrue(value.intersects(rect(10, 0, 10, 10)))
        XCTAssertTrue(value.intersects(rect(0, 10, 10, 10)))
        XCTAssertTrue(value.intersects(rect(10, 10, 1, 1)))
        XCTAssertFalse(value.intersects(rect(10.001, 0, 10, 10)))
        XCTAssertFalse(value.intersects(rect(-10.001, 0, 10, 10)))
    }

    func testIntersectionOverlapping() {
        let intersection = rect(0, 0, 10, 10).intersection(rect(5, 5, 10, 10))
        XCTAssertNotNil(intersection)
        assertRect(intersection!, rect(5, 5, 5, 5))
    }

    func testIntersectionOfEdgeTouchingRectsIsEmptyButNotNil() {
        let intersection = rect(0, 0, 10, 10).intersection(rect(10, 0, 10, 10))
        XCTAssertNotNil(intersection)
        XCTAssertTrue(intersection!.isEmpty)
        XCTAssertEqual(intersection!.width, 0)
        XCTAssertEqual(intersection!.height, 10)
    }

    func testIntersectionOfDisjointRectsIsNil() {
        XCTAssertNil(rect(0, 0, 10, 10).intersection(rect(20, 20, 10, 10)))
        XCTAssertNil(rect(0, 0, 10, 10).intersection(rect(10.5, 0, 10, 10)))
    }

    func testEncloses() {
        let outer = rect(0, 0, 100, 100)
        XCTAssertTrue(outer.encloses(rect(0, 0, 100, 100)))
        XCTAssertTrue(outer.encloses(rect(10, 10, 20, 20)))
        XCTAssertTrue(outer.encloses(rect(0, 0, 100, 0)), "Zero-height rect on an edge is enclosed")
        XCTAssertFalse(outer.encloses(rect(100, 0, 10, 10)))
        XCTAssertFalse(outer.encloses(rect(0, 0, 101, 100)))
        XCTAssertFalse(outer.encloses(rect(-1, 0, 10, 10)))
    }

    // MARK: Combining

    func testUnion() {
        assertRect(rect(0, 0, 10, 10).union(rect(5, 5, 10, 10)), rect(0, 0, 15, 15))
        assertRect(rect(0, 0, 10, 10).union(rect(20, 30, 5, 5)), rect(0, 0, 25, 35))
        // Union is symmetric.
        assertRect(rect(20, 30, 5, 5).union(rect(0, 0, 10, 10)), rect(0, 0, 25, 35))
    }

    func testBounding() {
        XCTAssertNil(CanvasRect.bounding([]))
        assertRect(CanvasRect.bounding([rect(0, 0, 10, 10)])!, rect(0, 0, 10, 10))
        assertRect(
            CanvasRect.bounding([rect(0, 0, 10, 10), rect(20, 5, 10, 10), rect(-5, -5, 2, 2)])!,
            rect(-5, -5, 35, 20)
        )
    }

    func testBoundingIgnoresOrder() {
        let a = rect(0, 0, 10, 10)
        let b = rect(50, 50, 10, 10)
        XCTAssertEqual(CanvasRect.bounding([a, b]), CanvasRect.bounding([b, a]))
    }

    // MARK: Insets, offsets, edges, scaling

    func testInsetAndExpand() {
        let value = rect(0, 0, 100, 50)
        assertRect(value.insetBy(10), rect(10, 10, 80, 30))
        assertRect(value.insetBy(0), value)
        assertRect(value.expandedBy(5), rect(-5, -5, 110, 60))
        assertRect(value.expandedBy(-10), rect(10, 10, 80, 30))
    }

    func testInsetCannotProduceNegativeSize() {
        let shrunk = rect(0, 0, 10, 10).insetBy(20)
        XCTAssertEqual(shrunk.width, 0)
        XCTAssertEqual(shrunk.height, 0)
        XCTAssertTrue(shrunk.isEmpty)
    }

    func testOffsetBy() {
        assertRect(rect(0, 0, 10, 10).offsetBy(dx: 5, dy: -5), rect(5, -5, 10, 10))
        assertRect(rect(0, 0, 10, 10).offsetBy(pt(-3, 7)), rect(-3, 7, 10, 10))
        // Offsetting a non-standardized rect standardizes it.
        assertRect(CanvasRect(origin: pt(10, 10), size: sz(-10, -10)).offsetBy(dx: 1, dy: 2), rect(1, 2, 10, 10))
    }

    func testTranslated() {
        assertRect(rect(0, 0, 10, 10).translated(to: pt(7, 8)), rect(7, 8, 10, 10))
    }

    func testEdgePinning() {
        let value = rect(0, 0, 10, 10)
        assertRect(value.withMinX(20).standardized, rect(10, 0, 10, 10))
        assertRect(value.withMinY(20).standardized, rect(0, 10, 10, 10))
        assertRect(value.withMaxX(5), rect(0, 0, 5, 10))
        assertRect(value.withMaxY(5), rect(0, 0, 10, 5))
    }

    func testScaledKeepsCenter() {
        let scaled = rect(0, 0, 10, 20).scaled(by: 2)
        assertRect(scaled, rect(-5, -10, 20, 40))
        assertPoint(scaled.center, rect(0, 0, 10, 20).center)
    }

    // MARK: distance

    func testDistanceFromPointToRect() {
        let value = rect(10, 10, 10, 10)
        XCTAssertEqual(Geometry.distance(from: pt(15, 15), to: value), 0, "Inside is zero")
        XCTAssertEqual(Geometry.distance(from: pt(0, 15), to: value), 10, "Left")
        XCTAssertEqual(Geometry.distance(from: pt(15, 0), to: value), 10, "Above")
        XCTAssertEqual(Geometry.distance(from: pt(20, 0), to: value), 10, "Above the right edge")
        XCTAssertEqual(Geometry.distance(from: pt(0, 0), to: value), (200.0).squareRoot(), accuracy: 1e-12, "Corner")
        XCTAssertEqual(Geometry.distance(from: pt(10, 10), to: value), 0, "On the corner")
    }

    // MARK: CanvasPoint

    func testCanvasPointMath() {
        XCTAssertEqual(pt(3, 4).length, 5)
        XCTAssertEqual(pt(1, 2).distance(to: pt(4, 6)), 5)
        assertPoint(pt(1, 2) + pt(3, 4), pt(4, 6))
        assertPoint(pt(4, 6) - pt(1, 2), pt(3, 4))
        assertPoint(pt(1, 2) * 3, pt(3, 6))
        assertPoint(pt(3, 6) / 3, pt(1, 2))
        assertPoint(-pt(1, -2), pt(-1, 2))
        XCTAssertEqual(CanvasPoint.zero, pt(0, 0))
    }

    func testCanvasPointRounded() {
        assertPoint(pt(13, -27).rounded(to: 10), pt(10, -30))
        assertPoint(pt(13, -27).rounded(to: 1), pt(13, -27))
        assertPoint(pt(1.49, 1.5).rounded(to: 1), pt(1, 2))
        assertPoint(pt(13, -27).rounded(to: 0), pt(13, -27), "Non-positive scale is a no-op")
    }

    func testCanvasPointCGPointBridge() {
        let point = CanvasPoint(CGPoint(x: 3.5, y: -4.25))
        assertPoint(point, pt(3.5, -4.25))
        XCTAssertEqual(point.cgPoint, CGPoint(x: 3.5, y: -4.25))
    }

    // MARK: CanvasSize

    func testCanvasSizeAspectRatio() {
        XCTAssertEqual(sz(16, 9).aspectRatio, 16.0 / 9.0, accuracy: 1e-12)
        XCTAssertEqual(sz(10, 0).aspectRatio, 1)
        XCTAssertEqual(CanvasSize.zero, sz(0, 0))
        XCTAssertEqual(CanvasSize(CGSize(width: 4, height: 2)), sz(4, 2))
    }

    // MARK: Geometry utilities

    func testClamp() {
        XCTAssertEqual(Geometry.clamp(5, 0, 10), 5)
        XCTAssertEqual(Geometry.clamp(-5, 0, 10), 0)
        XCTAssertEqual(Geometry.clamp(15, 0, 10), 10)
        XCTAssertEqual(Geometry.clamp(0.5, 0.0, 1.0), 0.5)
    }

    func testNormalizedDegrees() {
        XCTAssertEqual(Geometry.normalizedDegrees(0), 0, accuracy: 1e-12)
        XCTAssertEqual(Geometry.normalizedDegrees(90), 90, accuracy: 1e-12)
        XCTAssertEqual(Geometry.normalizedDegrees(180), 180, accuracy: 1e-12)
        XCTAssertEqual(Geometry.normalizedDegrees(181), -179, accuracy: 1e-12)
        XCTAssertEqual(Geometry.normalizedDegrees(-180), 180, accuracy: 1e-12)
        XCTAssertEqual(Geometry.normalizedDegrees(-181), 179, accuracy: 1e-12)
        XCTAssertEqual(Geometry.normalizedDegrees(360), 0, accuracy: 1e-12)
        XCTAssertEqual(Geometry.normalizedDegrees(540), 180, accuracy: 1e-12)
        XCTAssertEqual(Geometry.normalizedDegrees(-540), 180, accuracy: 1e-12)
    }
}
