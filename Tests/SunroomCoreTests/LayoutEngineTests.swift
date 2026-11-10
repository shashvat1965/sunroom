import XCTest
@testable import SunroomCore

final class LayoutEngineTests: XCTestCase {

    private let square = sz(100, 100)

    // MARK: Grid

    func testGridUsesRoughlySquareColumnCount() {
        let frames = LayoutEngine.grid(sizes: Array(repeating: square, count: 4), spacing: 40)
        // ceil(sqrt(4)) == 2 columns, each 100 wide with 40 spacing.
        XCTAssertEqual(frames, [
            rect(0, 0, 100, 100),
            rect(140, 0, 100, 100),
            rect(0, 140, 100, 100),
            rect(140, 140, 100, 100),
        ])
    }

    func testGridHonorsExplicitColumnCount() {
        let frames = LayoutEngine.grid(
            sizes: Array(repeating: square, count: 5),
            spacing: 10,
            columns: 3
        )
        XCTAssertEqual(frames.count, 5)
        XCTAssertEqual(frames[0].origin, pt(0, 0))
        XCTAssertEqual(frames[1].origin, pt(110, 0))
        XCTAssertEqual(frames[2].origin, pt(220, 0))
        XCTAssertEqual(frames[3].origin, pt(0, 110))
        XCTAssertEqual(frames[4].origin, pt(110, 110))
    }

    func testGridRowHeightUsesTallestItem() {
        let frames = LayoutEngine.grid(
            sizes: [sz(10, 10), sz(10, 200), sz(10, 50), sz(10, 50)],
            spacing: 10,
            columns: 2
        )
        XCTAssertEqual(frames[2].origin.y, 210, "Second row starts below the 200pt item")
        XCTAssertEqual(frames[2].origin.x, 0)
        XCTAssertEqual(frames[3].origin.x, 20)
    }

    func testGridPreservesInputOrder() {
        let sizes = [sz(10, 20), sz(30, 40), sz(50, 60), sz(70, 80), sz(90, 100)]
        let frames = LayoutEngine.grid(sizes: sizes, origin: pt(7, 11), spacing: 5, columns: 2)
        XCTAssertEqual(frames.map(\.width), [10, 30, 50, 70, 90])
        XCTAssertEqual(frames.map(\.height), [20, 40, 60, 80, 100])
        XCTAssertEqual(frames[0].origin, pt(7, 11))
    }

    func testGridHandlesEmptyInput() {
        XCTAssertTrue(LayoutEngine.grid(sizes: []).isEmpty)
        XCTAssertTrue(LayoutEngine.grid(sizes: [], columns: 0).isEmpty)
    }

    func testGridHasNoOverlaps() {
        var sizes: [CanvasSize] = []
        for index in 0..<17 {
            sizes.append(sz(Double(80 + index * 3), Double(40 + index * 7)))
        }
        let frames = LayoutEngine.grid(sizes: sizes, spacing: 24)
        assertNoOverlaps(frames)
    }

    // MARK: Rows / columns

    func testRowsStacksHorizontallyTopAligned() {
        let frames = LayoutEngine.rows(
            sizes: [sz(100, 50), sz(60, 80), sz(40, 30)],
            origin: pt(10, 20),
            spacing: 5
        )
        XCTAssertEqual(frames, [
            rect(10, 20, 100, 50),
            rect(115, 20, 60, 80),
            rect(180, 20, 40, 30),
        ])
    }

    func testColumnsStacksVerticallyLeadingAligned() {
        let frames = LayoutEngine.columns(
            sizes: [sz(100, 50), sz(60, 80), sz(40, 30)],
            origin: pt(10, 20),
            spacing: 5
        )
        XCTAssertEqual(frames, [
            rect(10, 20, 100, 50),
            rect(10, 75, 60, 80),
            rect(10, 160, 40, 30),
        ])
    }

    func testRowsAndColumnsHaveNoOverlaps() {
        var sizes: [CanvasSize] = []
        for index in 0..<8 {
            sizes.append(sz(Double(20 + index), Double(30 + index * 2)))
        }
        assertNoOverlaps(LayoutEngine.rows(sizes: sizes, spacing: 12))
        assertNoOverlaps(LayoutEngine.columns(sizes: sizes, spacing: 12))
    }

    func testRowsAndColumnsEmptyInput() {
        XCTAssertTrue(LayoutEngine.rows(sizes: []).isEmpty)
        XCTAssertTrue(LayoutEngine.columns(sizes: []).isEmpty)
    }

    // MARK: Radial

    func testRadialPlacesCentersOnACircle() {
        let center = pt(500, 400)
        let radius = 250.0
        let frames = LayoutEngine.radial(
            sizes: Array(repeating: sz(100, 100), count: 4),
            center: center,
            radius: radius
        )

        XCTAssertEqual(frames.count, 4)
        let expectedAngles: [Double] = [0, .pi / 2, .pi, 3 * .pi / 2]
        for (index, frame) in frames.enumerated() {
            XCTAssertEqual(frame.center.x, center.x + cos(expectedAngles[index]) * radius, accuracy: 1e-9)
            XCTAssertEqual(frame.center.y, center.y + sin(expectedAngles[index]) * radius, accuracy: 1e-9)
            XCTAssertEqual(
                frame.center.distance(to: center),
                radius,
                accuracy: 1e-9,
                "Frame \(frame) should sit on the circle"
            )
        }
    }

    func testRadialDerivesRadiusWhenOmitted() {
        let frames = LayoutEngine.radial(
            sizes: [sz(100, 100), sz(100, 100), sz(100, 100)],
            center: pt(0, 0)
        )
        XCTAssertEqual(frames.count, 3)
        XCTAssertGreaterThan(frames[0].center.x, 0)
    }

    func testRadialEmptyInput() {
        XCTAssertTrue(LayoutEngine.radial(sizes: []).isEmpty)
    }

    // MARK: Arrange / reflow

    func testArrangeDispatchesByMode() {
        let sizes = [sz(10, 20), sz(30, 40)]
        XCTAssertEqual(LayoutEngine.arrange(sizes: sizes, mode: .rows, spacing: 5), LayoutEngine.rows(sizes: sizes, spacing: 5))
        XCTAssertEqual(LayoutEngine.arrange(sizes: sizes, mode: .columns, spacing: 5), LayoutEngine.columns(sizes: sizes, spacing: 5))
        XCTAssertEqual(LayoutEngine.arrange(sizes: sizes, mode: .grid, spacing: 5), LayoutEngine.grid(sizes: sizes, spacing: 5))
        XCTAssertEqual(
            LayoutEngine.arrange(sizes: sizes, mode: .radial, origin: pt(100, 100)),
            LayoutEngine.radial(sizes: sizes, center: pt(100, 100))
        )
    }

    func testReflowPreservesInputOrder() {
        let a = makeNode(frame: rect(0, 500, 100, 50), id: UUID())
        let b = makeNode(frame: rect(0, 0, 60, 40), id: UUID())
        let c = makeNode(frame: rect(300, 0, 80, 30), id: UUID())
        let input = [a, b, c]

        let frames = LayoutEngine.reflow(nodes: input, mode: .rows, spacing: 10)

        XCTAssertEqual(frames.count, 3)
        // Result index maps to input index, not visual order.
        XCTAssertEqual(frames[1].width, b.frame.width)
        XCTAssertEqual(frames[2].width, c.frame.width)
        XCTAssertEqual(frames[0].width, a.frame.width)
        // Visual order is b, c, a, so a lands furthest right.
        XCTAssertGreaterThan(frames[0].minX, frames[1].minX)
        XCTAssertGreaterThan(frames[0].minX, frames[2].minX)
        XCTAssertLessThan(frames[1].minX, frames[2].minX)
    }

    func testReflowUsesTopmostLeftmostOrigin() {
        let a = makeNode(frame: rect(50, 100, 10, 10))
        let b = makeNode(frame: rect(20, 20, 10, 10))
        let frames = LayoutEngine.reflow(nodes: [a, b], mode: .columns, spacing: 5)
        // b is first in visual order, so it defines the origin.
        XCTAssertEqual(frames[1].origin, pt(20, 20))
        XCTAssertEqual(frames[0].origin, pt(20, 35))
    }

    func testReflowEmptyInput() {
        XCTAssertTrue(LayoutEngine.reflow(nodes: [], mode: .grid).isEmpty)
    }

    // MARK: Best arrangement

    func testBestArrangementFallsBackToRowsForTinyInputs() {
        XCTAssertEqual(LayoutEngine.bestArrangement(for: []), .rows)
        XCTAssertEqual(LayoutEngine.bestArrangement(for: [square]), .rows)
        XCTAssertEqual(LayoutEngine.bestArrangement(for: [square, square]), .rows)
    }

    func testBestArrangementPrefersGridForSquareItems() {
        let sizes = Array(repeating: square, count: 9)
        XCTAssertEqual(LayoutEngine.bestArrangement(for: sizes), .grid)
    }

    func testBestArrangementAlwaysReturnsACandidate() {
        var rng = LCG(seed: 7)
        for count in 3...20 {
            let sizes = (0..<count).map { _ in
                sz(rng.double(in: 20...300), rng.double(in: 20...300))
            }
            let arrangement = LayoutEngine.bestArrangement(for: sizes)
            XCTAssertTrue(
                [LayoutEngine.Arrangement.grid, .rows, .columns].contains(arrangement),
                "Unexpected radial arrangement for \(count) items"
            )
        }
    }

    // MARK: Level of detail

    func testLevelOfDetailThresholds() {
        XCTAssertEqual(LevelOfDetail.forZoom(0.01), .silhouette)
        XCTAssertEqual(LevelOfDetail.forZoom(0.079), .silhouette)
        XCTAssertEqual(LevelOfDetail.forZoom(0.08), .blocks)
        XCTAssertEqual(LevelOfDetail.forZoom(0.279), .blocks)
        XCTAssertEqual(LevelOfDetail.forZoom(0.28), .compact)
        XCTAssertEqual(LevelOfDetail.forZoom(0.619), .compact)
        XCTAssertEqual(LevelOfDetail.forZoom(0.62), .full)
        XCTAssertEqual(LevelOfDetail.forZoom(1), .full)
        XCTAssertEqual(LevelOfDetail.forZoom(12), .full)
    }

    func testLevelOfDetailFlags() {
        XCTAssertTrue(LevelOfDetail.full.showsText)
        XCTAssertTrue(LevelOfDetail.compact.showsText)
        XCTAssertFalse(LevelOfDetail.blocks.showsText)
        XCTAssertFalse(LevelOfDetail.silhouette.showsText)
        XCTAssertTrue(LevelOfDetail.full.showsSnapshots)
        XCTAssertFalse(LevelOfDetail.compact.showsSnapshots)
        XCTAssertTrue(LevelOfDetail.full.showsControls)
        XCTAssertFalse(LevelOfDetail.blocks.showsControls)
    }

    // MARK: Minimap projection

    func testMinimapProjectionPointRoundTrip() {
        let projection = MinimapProjection(
            canvasBounds: rect(0, 0, 1000, 500),
            viewport: rect(0, 0, 100, 100),
            minimapSize: sz(200, 200),
            padding: 8
        )

        for point in [pt(0, 0), pt(10, 20), pt(500, 250), pt(1000, 500), pt(-20, 30)] {
            let roundTripped = projection.canvasPoint(for: projection.point(for: point))
            assertPoint(roundTripped, point, accuracy: 1e-9)
        }
    }

    func testMinimapProjectionRectRoundTrip() {
        let projection = MinimapProjection(
            canvasBounds: rect(-100, -50, 500, 300),
            viewport: rect(0, 0, 100, 100),
            minimapSize: sz(160, 120)
        )
        let original = rect(10, 20, 200, 100)
        let mapped = projection.rect(for: original)
        XCTAssertEqual(mapped.width, original.width * projection.scale, accuracy: 1e-9)
        XCTAssertEqual(mapped.height, original.height * projection.scale, accuracy: 1e-9)
        // The rect's corners survive the round trip through minimap space.
        assertPoint(projection.canvasPoint(for: mapped.origin), original.origin, accuracy: 1e-9)
        assertPoint(
            projection.canvasPoint(for: pt(mapped.maxX, mapped.maxY)),
            pt(original.maxX, original.maxY),
            accuracy: 1e-9
        )
    }

    func testMinimapProjectionFitsContentInsideViewport() {
        let projection = MinimapProjection(
            canvasBounds: rect(-200, -100, 800, 400),
            viewport: rect(0, 0, 10, 10),
            minimapSize: sz(200, 100),
            padding: 10
        )
        let mapped = projection.rect(for: rect(-200, -100, 800, 400))
        XCTAssertGreaterThanOrEqual(mapped.minX, 9.999)
        XCTAssertGreaterThanOrEqual(mapped.minY, 9.999)
        XCTAssertLessThanOrEqual(mapped.maxX, 190.001)
        XCTAssertLessThanOrEqual(mapped.maxY, 90.001)
    }

    func testMinimapBoundsUnionsContentAndViewport() {
        let bounds = MinimapProjection.bounds(
            content: rect(0, 0, 100, 100),
            viewport: rect(50, 50, 100, 100)
        )
        // Union is 150x150, then expanded by 5% of the content width on each side.
        XCTAssertEqual(bounds, rect(-5, -5, 160, 160))
    }

    func testMinimapBoundsWithoutContentUsesViewport() {
        let viewport = rect(10, 20, 30, 40)
        XCTAssertEqual(MinimapProjection.bounds(content: nil, viewport: viewport), viewport)
        XCTAssertEqual(MinimapProjection.bounds(content: .zero, viewport: viewport), viewport)
    }
}
