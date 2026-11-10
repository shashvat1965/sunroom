import XCTest
@testable import SunroomCore

final class SnappingTests: XCTestCase {

    // MARK: Edge snapping

    func testSnapsMovingEdgeToTargetEdge() {
        let target = rect(0, 0, 100, 100)
        let moving = rect(98, 300, 50, 50)

        let result = Snapping.snap(rect: moving, targets: [target])

        XCTAssertTrue(result.snappedHorizontally)
        XCTAssertFalse(result.snappedVertically)
        assertPoint(result.adjustedOrigin, pt(100, 300))
        XCTAssertEqual(result.guides.count, 1)

        let guide = result.guides[0]
        XCTAssertEqual(guide.orientation, .vertical)
        XCTAssertEqual(guide.position, 100)
        XCTAssertEqual(guide.start, 0, "Guide spans both rects")
        XCTAssertEqual(guide.end, 350)
    }

    func testSnapsTrailingEdgeToTargetLeadingEdge() {
        let target = rect(200, 0, 100, 100)
        let moving = rect(148, 300, 50, 50) // maxX = 198, target minX = 200

        let result = Snapping.snap(rect: moving, targets: [target])

        XCTAssertTrue(result.snappedHorizontally)
        assertPoint(result.adjustedOrigin, pt(150, 300))
        XCTAssertEqual(result.guides.first?.position, 200)
    }

    func testSnapsVerticalEdgesIndependently() {
        let target = rect(0, 0, 100, 100)
        let moving = rect(300, 97, 50, 50) // minY 97 -> 100

        let result = Snapping.snap(rect: moving, targets: [target])

        XCTAssertFalse(result.snappedHorizontally)
        XCTAssertTrue(result.snappedVertically)
        assertPoint(result.adjustedOrigin, pt(300, 100))
        XCTAssertEqual(result.guides.first?.orientation, .horizontal)
        XCTAssertEqual(result.guides.first?.position, 100)
    }

    // MARK: Center snapping

    func testSnapsCenters() {
        let target = rect(0, 0, 100, 100)
        let moving = rect(20, 300, 60, 40) // centers x both 50

        let result = Snapping.snap(rect: moving, targets: [target])

        XCTAssertTrue(result.snappedHorizontally)
        XCTAssertFalse(result.snappedVertically)
        assertPoint(result.adjustedOrigin, pt(20, 300), "Already centered, no movement")
        XCTAssertEqual(result.guides.first?.position, 50)
    }

    func testCenterSnappingCanBeDisabled() {
        var configuration = SnapConfiguration.default
        configuration.snapToCenters = false
        configuration.snapToEdges = true

        let target = rect(0, 0, 100, 100)
        let moving = rect(20, 300, 60, 40)

        let result = Snapping.snap(rect: moving, targets: [target], configuration: configuration)
        XCTAssertFalse(result.didSnap)
        assertPoint(result.adjustedOrigin, pt(20, 300))
    }

    // MARK: Candidate priority

    func testClosestCandidateWins() {
        let near = rect(0, 0, 100, 100)    // right edge at 100, delta +1
        let farther = rect(3, 0, 100, 100) // right edge at 103, delta +4
        let moving = rect(99, 300, 50, 50)

        let result = Snapping.snap(rect: moving, targets: [farther, near])

        XCTAssertTrue(result.snappedHorizontally)
        assertPoint(result.adjustedOrigin, pt(100, 300))
        XCTAssertEqual(result.guides.first?.position, 100)
    }

    func testToleranceBoundaryIsInclusive() {
        let target = rect(0, 0, 100, 100)
        let moving = rect(106, 300, 50, 50) // delta -6 exactly

        let result = Snapping.snap(rect: moving, targets: [target], configuration: .default)
        XCTAssertTrue(result.snappedHorizontally)
        assertPoint(result.adjustedOrigin, pt(100, 300))
    }

    func testToleranceScalesWithZoom() {
        let target = rect(0, 0, 100, 100)
        let moving = rect(107, 300, 50, 50) // delta -7: outside a 6pt tolerance

        let atOne = Snapping.snap(rect: moving, targets: [target], configuration: .default)
        XCTAssertFalse(atOne.didSnap)

        let zoomedOut = SnapConfiguration.default.scaled(forZoom: 0.5) // tolerance 12
        XCTAssertEqual(zoomedOut.tolerance, 12)
        let snapped = Snapping.snap(rect: moving, targets: [target], configuration: zoomedOut)
        XCTAssertTrue(snapped.snappedHorizontally)
        assertPoint(snapped.adjustedOrigin, pt(100, 300))

        let zoomedIn = SnapConfiguration.default.scaled(forZoom: 2) // tolerance 3
        XCTAssertEqual(zoomedIn.tolerance, 3)
        XCTAssertFalse(Snapping.snap(rect: moving, targets: [target], configuration: zoomedIn).didSnap)
    }

    func testScalingToleranceNeverDividesByZero() {
        let scaled = SnapConfiguration(tolerance: 6, snapToEdges: false, snapToCenters: false)
            .scaled(forZoom: 0)
        XCTAssertEqual(scaled.tolerance, 60_000, accuracy: 1e-9)
    }

    // MARK: Grid

    func testGridSnapping() {
        let configuration = SnapConfiguration(
            tolerance: 6,
            snapToGrid: true,
            gridSpacing: 48,
            snapToEdges: false,
            snapToCenters: false
        )
        let moving = rect(95, 200, 50, 50) // x -> 96, y 200 is 8 from 192

        let result = Snapping.snap(rect: moving, targets: [], configuration: configuration)

        assertPoint(result.adjustedOrigin, pt(96, 200))
        XCTAssertTrue(result.snappedHorizontally)
        XCTAssertFalse(result.snappedVertically)
        XCTAssertEqual(result.guides.first?.orientation, .vertical)
        XCTAssertEqual(result.guides.first?.position, 96)
    }

    func testGridSnapsBothAxes() {
        let configuration = SnapConfiguration(
            tolerance: 6,
            snapToGrid: true,
            gridSpacing: 48,
            snapToEdges: false,
            snapToCenters: false
        )
        let result = Snapping.snap(rect: rect(95, 49, 10, 10), targets: [], configuration: configuration)
        assertPoint(result.adjustedOrigin, pt(96, 48))
        XCTAssertTrue(result.snappedHorizontally)
        XCTAssertTrue(result.snappedVertically)
    }

    func testGridDoesNotOverrideCloserTargetSnap() {
        let configuration = SnapConfiguration(
            tolerance: 6,
            snapToGrid: true,
            gridSpacing: 48,
            snapToEdges: true,
            snapToCenters: false
        )
        let target = rect(0, 0, 100, 100)
        let moving = rect(102, 300, 10, 10) // target edge delta -2, grid delta -6

        let result = Snapping.snap(rect: moving, targets: [target], configuration: configuration)
        assertPoint(result.adjustedOrigin, pt(100, 300))
    }

    // MARK: Multi-selection

    func testMultiSelectionBoundsSnapAsOneUnit() {
        var document = makeDocument(nodes: [
            makeNode(frame: rect(98, 300, 60, 40)),
            makeNode(frame: rect(150, 340, 20, 40)),
        ])
        let selection = ids(of: document)
        let bounds = try! XCTUnwrap(document.bounds(of: selection))
        XCTAssertEqual(bounds, rect(98, 300, 72, 80))

        let target = rect(0, 0, 100, 100)
        let result = Snapping.snap(bounds: bounds, targets: [target])

        assertPoint(result.adjustedOrigin, pt(100, 300))

        // Applying the same delta to every selected node keeps the selection rigid.
        let delta = result.adjustedOrigin - bounds.origin
        document.move(ids: selection, by: delta)
        XCTAssertEqual(document.bounds(of: selection), rect(100, 300, 72, 80))
    }

    // MARK: Passthrough & disabled

    func testNoSnapWhenNothingIsNear() {
        let moving = rect(500, 500, 50, 50)
        let result = Snapping.snap(rect: moving, targets: [rect(0, 0, 100, 100)])

        XCTAssertFalse(result.didSnap)
        XCTAssertTrue(result.guides.isEmpty)
        assertPoint(result.adjustedOrigin, pt(500, 500))
    }

    func testNoTargetsAndGridOffIsPassthrough() {
        let moving = rect(17, 23, 50, 50)
        let result = Snapping.snap(rect: moving, targets: [], configuration: .default)
        assertPoint(result.adjustedOrigin, pt(17, 23))
        XCTAssertFalse(result.didSnap)
    }

    func testDisabledConfigurationIsPassthrough() {
        let moving = rect(99, 99, 50, 50)
        let result = Snapping.snap(rect: moving, targets: [rect(0, 0, 100, 100)], configuration: .disabled)
        assertPoint(result.adjustedOrigin, pt(99, 99))
        XCTAssertFalse(result.didSnap)
    }

    func testNonStandardizedMovingRectIsStandardized() {
        let moving = CanvasRect(origin: pt(200, 300), size: sz(-50, -50)) // standardized 150..200, 250..300
        let result = Snapping.snap(rect: moving, targets: [rect(0, 0, 150, 100)])
        assertPoint(result.adjustedOrigin, pt(150, 250))
    }

    // MARK: Guides

    func testGuidesHaveOrientationPositionAndSpan() {
        let target = rect(0, 0, 100, 100)
        let moving = rect(98, 97, 10, 10) // y 97 -> 100, x 98 -> 100

        let result = Snapping.snap(rect: moving, targets: [target])
        assertPoint(result.adjustedOrigin, pt(100, 100))
        XCTAssertEqual(result.guides.count, 2)

        let vertical = try! XCTUnwrap(result.guides.first { $0.orientation == .vertical })
        XCTAssertEqual(vertical.position, 100)
        XCTAssertEqual(vertical.start, 0)
        XCTAssertEqual(vertical.end, 107)

        let horizontal = try! XCTUnwrap(result.guides.first { $0.orientation == .horizontal })
        XCTAssertEqual(horizontal.position, 100)
        XCTAssertEqual(horizontal.start, 0)
        XCTAssertEqual(horizontal.end, 108)
    }

    func testAlignmentGuidesForSharedEdgesAndCenters() {
        let a = rect(10, 10, 100, 100)
        let b = rect(10, 150, 100, 50)

        let guides = Snapping.alignmentGuides(between: a, and: b)

        let verticalPositions = guides.filter { $0.orientation == .vertical }.map(\.position).sorted()
        XCTAssertEqual(verticalPositions, [10, 60, 110], "left, center, right align")
        XCTAssertTrue(guides.allSatisfy { $0.start == 10 && $0.end == 200 })
    }

    func testAlignmentGuidesForSharedHorizontalEdges() {
        let a = rect(0, 0, 100, 100)
        let b = rect(150, 0, 50, 100)

        let guides = Snapping.alignmentGuides(between: a, and: b)
        let horizontal = guides.filter { $0.orientation == .horizontal }
        XCTAssertEqual(horizontal.map(\.position).sorted(), [0, 50, 100])
        XCTAssertTrue(guides.allSatisfy { $0.orientation == .horizontal })
    }

    func testAlignmentGuidesRespectTolerance() {
        let a = rect(0, 0, 100, 100)
        let b = rect(100.4, 0, 50, 100)
        // maxX of `a` is 0.4 away from minX of `b`; edges and horizontal
        // center lines line up, so four guides survive the default tolerance.
        XCTAssertEqual(Snapping.alignmentGuides(between: a, and: b).count, 4)

        // Tightening the tolerance drops only the near-miss vertical guide.
        let strict = Snapping.alignmentGuides(between: a, and: b, tolerance: 0.1)
        XCTAssertEqual(strict.count, 3)
        XCTAssertTrue(strict.allSatisfy { $0.orientation == .horizontal })
    }
}
