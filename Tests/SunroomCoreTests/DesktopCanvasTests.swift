import XCTest
@testable import SunroomCore

final class DesktopCanvasTests: XCTestCase {

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CanvasRect {
        CanvasRect(x: x, y: y, width: w, height: h)
    }

    private var screen: CanvasRect { rect(0, 0, 1440, 900) }

    // MARK: Fitting

    func testFittingZoomShrinksLargeBounds() {
        let zoom = PlaneLayoutEngine.fittingZoom(for: rect(0, 0, 3000, 1000), in: screen)
        XCTAssertLessThan(zoom, 1)
        XCTAssertGreaterThan(zoom, 0.33)
    }

    func testFittingZoomClampsToMinimumForEnormousBounds() {
        let zoom = PlaneLayoutEngine.fittingZoom(for: rect(0, 0, 40000, 30000), in: screen)
        XCTAssertEqual(zoom, 0.34, accuracy: 0.0001)
    }

    func testFittingZoomNeverExceedsOne() {
        let zoom = PlaneLayoutEngine.fittingZoom(for: rect(0, 0, 200, 100), in: screen)
        XCTAssertEqual(zoom, 1.0, accuracy: 0.0001)
    }

    func testFittingZoomLeavesPadding() {
        let bounds = rect(0, 0, 1440, 900)
        let zoom = PlaneLayoutEngine.fittingZoom(for: bounds, in: screen, padding: 100)
        XCTAssertLessThanOrEqual(bounds.width * zoom, screen.width - 200 + 0.001)
        XCTAssertLessThanOrEqual(bounds.height * zoom, screen.height - 200 + 0.001)
    }

    // MARK: Cameras

    func testCameraFittingCentresBounds() {
        let bounds = rect(100, 200, 400, 300)
        let camera = PlaneLayoutEngine.camera(fitting: bounds, in: screen, zoom: 0.5)
        let mapped = camera.screenRect(fromCanvas: bounds)
        XCTAssertEqual(mapped.center.x, screen.midX, accuracy: 0.001)
        XCTAssertEqual(mapped.center.y, screen.midY, accuracy: 0.001)
    }

    func testCameraFocusingCentresSingleFrame() {
        let frame = rect(2000, 1200, 800, 600)
        let camera = PlaneLayoutEngine.camera(focusing: frame, in: screen, scale: 1)
        XCTAssertEqual(camera.zoom, 1)
        let mapped = camera.screenRect(fromCanvas: frame)
        XCTAssertEqual(mapped.center.x, screen.midX, accuracy: 0.001)
        XCTAssertEqual(mapped.center.y, screen.midY, accuracy: 0.001)
    }

    func testCameraRoundTripsPlanePoints() {
        let camera = PlaneLayoutEngine.camera(fitting: rect(-500, -300, 2200, 1500), in: screen, zoom: 0.42)
        let planePoint = CanvasPoint(x: 137, y: -42)
        let back = camera.canvasPoint(fromScreen: camera.screenPoint(fromCanvas: planePoint))
        XCTAssertEqual(back.x, planePoint.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, planePoint.y, accuracy: 1e-9)
    }

    // MARK: Normalise / parking / stacking

    func testNormaliseCentresTheCluster() {
        let frames = [rect(0, 0, 400, 300), rect(500, 200, 300, 200)]
        let result = PlaneLayoutEngine.normalise(frames: frames, into: screen)
        let union = CanvasRect.bounding(result)!
        XCTAssertEqual(union.center.x, screen.midX, accuracy: 0.01)
        XCTAssertEqual(union.center.y, screen.midY, accuracy: 0.01)
        // Relative arrangement is preserved.
        XCTAssertEqual(result[1].minX - result[0].minX, 500, accuracy: 0.001)
    }

    func testNormaliseLeavesEmptyInputAlone() {
        XCTAssertTrue(PlaneLayoutEngine.normalise(frames: [], into: screen).isEmpty)
    }

    func testParkingSpotSitsToTheRightAndDoesNotOverlap() {
        let occupied = [rect(0, 0, 400, 300)]
        let spot = PlaneLayoutEngine.parkingSpot(for: CanvasSize(width: 300, height: 200), avoiding: occupied)
        XCTAssertGreaterThanOrEqual(spot.minX, 400)
        XCTAssertFalse(spot.intersects(occupied[0]))
        XCTAssertEqual(spot.width, 300)
    }

    func testParkingSpotStartsAtOriginWhenEmpty() {
        let spot = PlaneLayoutEngine.parkingSpot(for: CanvasSize(width: 300, height: 200), avoiding: [])
        XCTAssertEqual(spot.origin, .zero)
    }

    func testStackingOffsetsTheFrame() {
        let stacked = PlaneLayoutEngine.stacked(rect(0, 0, 200, 100), onto: rect(500, 500, 400, 300))
        XCTAssertEqual(stacked.minX, 526)
        XCTAssertEqual(stacked.minY, 526)
        XCTAssertEqual(stacked.size, CanvasSize(width: 200, height: 100))
    }

    // MARK: Nearest

    func testNearestFindsDirectionalNeighbours() {
        let frames: [String: CanvasRect] = [
            "center": rect(1000, 1000, 200, 200),
            "left": rect(400, 1000, 200, 200),
            "right": rect(1600, 1000, 200, 200),
            "up": rect(1000, 400, 200, 200),
            "down": rect(1000, 1600, 200, 200)
        ]
        let reference = frames["center"]!
        XCTAssertEqual(PlaneLayoutEngine.nearest(to: reference, in: frames, direction: .left), "left")
        XCTAssertEqual(PlaneLayoutEngine.nearest(to: reference, in: frames, direction: .right), "right")
        XCTAssertEqual(PlaneLayoutEngine.nearest(to: reference, in: frames, direction: .up), "up")
        XCTAssertEqual(PlaneLayoutEngine.nearest(to: reference, in: frames, direction: .down), "down")
    }

    func testNearestReturnsNilWhenNothingIsInThatDirection() {
        let frames = ["a": rect(0, 0, 100, 100)]
        XCTAssertNil(PlaneLayoutEngine.nearest(to: frames["a"]!, in: frames, direction: .right))
    }

    func testNearestPrefersTheClosestWindow() {
        let frames: [String: CanvasRect] = [
            "origin": rect(0, 0, 100, 100),
            "near": rect(300, 20, 100, 100),
            "far": rect(900, 0, 100, 100)
        ]
        XCTAssertEqual(PlaneLayoutEngine.nearest(to: frames["origin"]!, in: frames, direction: .right), "near")
    }

    // MARK: Tiling

    func testTileZoneDetectsEdgesAndCorners() {
        let area = rect(0, 0, 1000, 1000)
        XCTAssertEqual(TileZone.zone(for: CanvasPoint(x: 50, y: 500), in: area), .left)
        XCTAssertEqual(TileZone.zone(for: CanvasPoint(x: 950, y: 500), in: area), .right)
        XCTAssertEqual(TileZone.zone(for: CanvasPoint(x: 500, y: 50), in: area), .top)
        XCTAssertEqual(TileZone.zone(for: CanvasPoint(x: 500, y: 950), in: area), .bottom)
        XCTAssertEqual(TileZone.zone(for: CanvasPoint(x: 50, y: 50), in: area), .topLeft)
        XCTAssertEqual(TileZone.zone(for: CanvasPoint(x: 950, y: 950), in: area), .bottomRight)
    }

    func testTileZoneDeadZoneInTheMiddle() {
        XCTAssertNil(TileZone.zone(for: CanvasPoint(x: 500, y: 500), in: rect(0, 0, 1000, 1000)))
    }

    func testTileZoneFramesDoNotOverlapAndStayInside() {
        let area = rect(0, 0, 1200, 800)
        var frames: [CanvasRect] = []
        for zone in TileZone.allCases {
            let frame = zone.frame(in: area)
            XCTAssertTrue(area.insetBy(-0.001).encloses(frame), "\(zone) escaped the area")
            frames.append(frame)
        }
        XCTAssertFalse(frames[0].intersects(frames[1]), "left and right must not overlap")
        XCTAssertFalse(frames[2].intersects(frames[3]), "top and bottom must not overlap")
        XCTAssertEqual(frames[0].height, frames[1].height, accuracy: 0.001)
    }

    func testTileFillUsesTheWholeAreaMinusGap() {
        let area = rect(0, 0, 1000, 800)
        let filled = TileZone.fill.frame(in: area, gap: 10)
        XCTAssertEqual(filled, area.insetBy(10))
    }

    // MARK: Identity

    func testIdentityKeyNormalisesWhitespaceCaseAndDashes() {
        let a = PlaneWindow.identityKey(bundleIdentifier: "com.apple.Safari", appName: "Safari", title: " Design — Notes ")
        let b = PlaneWindow.identityKey(bundleIdentifier: "com.apple.Safari", appName: "Safari", title: "design - notes")
        XCTAssertEqual(a, b)
    }

    func testIdentityFallsBackToAppNameWithoutBundle() {
        let key = PlaneWindow.identityKey(bundleIdentifier: nil, appName: "Terminal", title: "zsh")
        XCTAssertTrue(key.hasPrefix("Terminal|"))
    }

    // MARK: Layout

    func testPlaneLayoutBoundsUnion() {
        let a = PlaneWindow(id: "a", windowNumber: 1, ownerPID: 1, appName: "A", title: "", bundleIdentifier: nil, planeFrame: rect(0, 0, 100, 100), originalFrame: rect(0, 0, 100, 100))
        let b = PlaneWindow(id: "b", windowNumber: 2, ownerPID: 2, appName: "B", title: "", bundleIdentifier: nil, planeFrame: rect(200, 100, 100, 100), originalFrame: rect(200, 100, 100, 100))
        let layout = PlaneLayout(camera: .identity, windows: [a, b])
        XCTAssertEqual(layout.bounds, rect(0, 0, 300, 200))
    }

    func testPlaneWindowDisplayLabelFallsBackToAppName() {
        let window = PlaneWindow(id: "a", windowNumber: 1, ownerPID: 1, appName: "Finder", title: "   ", bundleIdentifier: nil, planeFrame: .zero, originalFrame: .zero)
        XCTAssertEqual(window.displayLabel, "Finder")
    }
}
