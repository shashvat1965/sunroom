import XCTest
@testable import SunroomCore

final class CanvasTransformTests: XCTestCase {

    // MARK: Mapping

    func testIdentityMappingIsIdentity() {
        let transform = CanvasTransform.identity
        assertPoint(transform.screenPoint(fromCanvas: pt(12, -34)), pt(12, -34))
        assertPoint(transform.canvasPoint(fromScreen: pt(12, -34)), pt(12, -34))
    }

    func testCanvasScreenMappingRoundTrips() {
        let transform = CanvasTransform(translation: pt(120, -40), zoom: 2.5)
        let samples = [pt(0, 0), pt(10, 20), pt(-500, 900), pt(1e6, -1e6)]
        for point in samples {
            let roundTripped = transform.canvasPoint(fromScreen: transform.screenPoint(fromCanvas: point))
            assertPoint(roundTripped, point, accuracy: 1e-9, "roundtrip for \(point)")
        }
    }

    func testScreenRectMappingRoundTrips() {
        let transform = CanvasTransform(translation: pt(-30, 70), zoom: 0.75)
        let original = rect(10, 20, 300, 120)
        let screen = transform.screenRect(fromCanvas: original)
        assertPoint(screen.origin, pt(10 * 0.75 - 30, 20 * 0.75 + 70))
        assertSize(screen.size, sz(225, 90))
        assertRect(transform.canvasRect(fromScreen: screen), original, accuracy: 1e-9)
    }

    func testDistanceMappingScalesWithZoom() {
        let transform = CanvasTransform(zoom: 3)
        XCTAssertEqual(transform.screenDistance(fromCanvas: 10), 30)
        XCTAssertEqual(transform.canvasDistance(fromScreen: 30), 10)
    }

    // MARK: Zoom anchoring

    func testZoomingKeepsAnchorPointFixed() {
        let start = CanvasTransform(translation: pt(40, -10), zoom: 1.25)
        let anchor = pt(300, 200)
        let anchorInCanvas = start.canvasPoint(fromScreen: anchor)

        let zoomed = start.zooming(to: 3.5, anchor: anchor)

        XCTAssertEqual(zoomed.zoom, 3.5)
        // The same canvas point is still under the anchor on screen.
        assertPoint(zoomed.screenPoint(fromCanvas: anchorInCanvas), anchor, accuracy: 1e-9)
        assertPoint(zoomed.canvasPoint(fromScreen: anchor), anchorInCanvas, accuracy: 1e-9)
    }

    func testZoomingByFactorIsRelative() {
        let start = CanvasTransform(translation: pt(10, 20), zoom: 1.5)
        let anchor = pt(100, 100)
        let zoomed = start.zooming(by: 2, anchor: anchor)
        XCTAssertEqual(zoomed.zoom, 3)
        assertPoint(
            zoomed.screenPoint(fromCanvas: start.canvasPoint(fromScreen: anchor)),
            anchor,
            accuracy: 1e-9
        )
    }

    func testZoomingByNonPositiveFactorIsNoOp() {
        let start = CanvasTransform(translation: pt(10, 20), zoom: 1.5)
        XCTAssertEqual(start.zooming(by: 0, anchor: pt(100, 100)), start)
        XCTAssertEqual(start.zooming(by: -2, anchor: pt(100, 100)), start)
    }

    // MARK: Zoom clamping

    func testInitClampsZoom() {
        XCTAssertEqual(CanvasTransform(zoom: 0).zoom, CanvasTransform.minZoom)
        XCTAssertEqual(CanvasTransform(zoom: -5).zoom, CanvasTransform.minZoom)
        XCTAssertEqual(CanvasTransform(zoom: 1_000).zoom, CanvasTransform.maxZoom)
        XCTAssertEqual(CanvasTransform(zoom: .infinity).zoom, CanvasTransform.maxZoom)
        XCTAssertEqual(CanvasTransform(zoom: 2).zoom, 2)
    }

    func testZoomingToClampsAndKeepsAnchorAtBounds() {
        let start = CanvasTransform(translation: pt(0, 0), zoom: 1)
        let anchor = pt(50, 60)
        let maxed = start.zooming(to: 1_000, anchor: anchor)
        XCTAssertEqual(maxed.zoom, CanvasTransform.maxZoom)
        assertPoint(
            maxed.screenPoint(fromCanvas: start.canvasPoint(fromScreen: anchor)),
            anchor,
            accuracy: 1e-9
        )

        let minned = start.zooming(to: 0.000001, anchor: anchor)
        XCTAssertEqual(minned.zoom, CanvasTransform.minZoom)
        assertPoint(
            minned.screenPoint(fromCanvas: start.canvasPoint(fromScreen: anchor)),
            anchor,
            accuracy: 1e-9
        )
    }

    func testZoomingToCurrentZoomReturnsSelf() {
        let start = CanvasTransform(translation: pt(1, 2), zoom: 2)
        XCTAssertEqual(start.zooming(to: 2, anchor: pt(300, 300)), start)

        let atMax = CanvasTransform(translation: pt(1, 2), zoom: CanvasTransform.maxZoom)
        XCTAssertEqual(
            atMax.zooming(to: 50, anchor: pt(300, 300)),
            atMax,
            "Target above max while already at max"
        )
    }

    // MARK: Fitting

    func testFittingCentersRectAndRespectsPadding() {
        let viewport = sz(1000, 800)
        let target = rect(0, 0, 3000, 2000)

        let fitted = CanvasTransform.identity.fitting(target, in: viewport, padding: 50, maxZoom: 4)

        // Available space is 900x700, so scale = min(0.3, 0.35) = 0.3.
        XCTAssertEqual(fitted.zoom, 0.3, accuracy: 1e-12)
        assertRect(fitted.screenRect(fromCanvas: target), rect(50, 100, 900, 600), accuracy: 1e-9)
        assertPoint(fitted.screenPoint(fromCanvas: target.center), pt(500, 400), accuracy: 1e-9)
    }

    func testFittingNeverZoomsBeyondMaxZoom() {
        let small = rect(0, 0, 10, 10)
        let fitted = CanvasTransform.identity.fitting(small, in: sz(1000, 800), padding: 50)
        XCTAssertEqual(fitted.zoom, 1)
        assertPoint(fitted.screenPoint(fromCanvas: small.center), pt(500, 400))
    }

    func testFittingHonorsCustomMaxZoom() {
        let small = rect(0, 0, 100, 100)
        let fitted = CanvasTransform.identity.fitting(small, in: sz(1000, 800), padding: 50, maxZoom: 2)
        XCTAssertEqual(fitted.zoom, 2)
        assertPoint(fitted.screenPoint(fromCanvas: small.center), pt(500, 400))
    }

    func testFittingDegenerateRectFallsBackToCentering() {
        let start = CanvasTransform(translation: pt(999, 999), zoom: 1.5)
        let degenerate = rect(10, 20, 0, 0)

        let fitted = start.fitting(degenerate, in: sz(800, 600), padding: 64)

        // Degenerate rects keep the current zoom and simply center the point.
        XCTAssertEqual(fitted.zoom, start.zoom)
        assertPoint(fitted.screenPoint(fromCanvas: pt(10, 20)), pt(400, 300))
    }

    func testFittingZeroViewportDoesNotCrashAndPreservesZoom() {
        let start = CanvasTransform(translation: pt(0, 0), zoom: 2)
        let fitted = start.fitting(rect(0, 0, 10, 10), in: sz(0, 0))
        XCTAssertEqual(fitted.zoom, 2)
        XCTAssertTrue(fitted.translation.x.isFinite)
        XCTAssertTrue(fitted.translation.y.isFinite)
    }

    func testFittingHugeViewportClampsToMaxZoom() {
        let fitted = CanvasTransform.identity.fitting(rect(0, 0, 1, 1), in: sz(100_000, 100_000))
        XCTAssertEqual(fitted.zoom, 1)
    }

    // MARK: Centering & viewport

    func testCenteringKeepsZoomAndPlacesPointInMiddle() {
        let start = CanvasTransform(translation: pt(-100, -100), zoom: 2)
        let centered = start.centering(on: pt(100, 50), in: sz(400, 300))
        XCTAssertEqual(centered.zoom, 2)
        assertPoint(centered.screenPoint(fromCanvas: pt(100, 50)), pt(200, 150))
    }

    func testVisibleCanvasRect() {
        let transform = CanvasTransform(translation: pt(100, 50), zoom: 2)
        let visible = transform.visibleCanvasRect(in: sz(800, 600))
        assertRect(visible, rect(-50, -25, 400, 300))
    }

    func testVisibleCanvasRectMatchesScreenCorners() {
        let transform = CanvasTransform(translation: pt(-17.5, 33.25), zoom: 0.6)
        let viewport = sz(1280, 720)
        let visible = transform.visibleCanvasRect(in: viewport)
        assertPoint(transform.screenPoint(fromCanvas: visible.origin), pt(0, 0), accuracy: 1e-9)
        assertPoint(
            transform.screenPoint(fromCanvas: pt(visible.maxX, visible.maxY)),
            pt(viewport.width, viewport.height),
            accuracy: 1e-9
        )
    }

    // MARK: Interpolation

    func testInterpolationEndpoints() {
        let from = CanvasTransform(translation: pt(0, 0), zoom: 1)
        let to = CanvasTransform(translation: pt(200, -100), zoom: 4)

        let atZero = CanvasTransform.interpolate(from: from, to: to, t: 0)
        let atOne = CanvasTransform.interpolate(from: from, to: to, t: 1)

        assertPoint(atZero.translation, from.translation)
        assertPoint(atOne.translation, to.translation)
        XCTAssertEqual(atZero.zoom, from.zoom, accuracy: 1e-12)
        XCTAssertEqual(atOne.zoom, to.zoom, accuracy: 1e-12)
    }

    func testInterpolationClampsParameter() {
        let from = CanvasTransform(translation: pt(0, 0), zoom: 1)
        let to = CanvasTransform(translation: pt(200, -100), zoom: 4)

        XCTAssertEqual(
            CanvasTransform.interpolate(from: from, to: to, t: -5),
            CanvasTransform.interpolate(from: from, to: to, t: 0)
        )
        XCTAssertEqual(
            CanvasTransform.interpolate(from: from, to: to, t: 5),
            CanvasTransform.interpolate(from: from, to: to, t: 1)
        )
    }

    func testInterpolationIsDeterministicAndUsesLogZoom() {
        let from = CanvasTransform(translation: pt(10, 20), zoom: 1)
        let to = CanvasTransform(translation: pt(110, 220), zoom: 4)

        let first = CanvasTransform.interpolate(from: from, to: to, t: 0.5)
        let second = CanvasTransform.interpolate(from: from, to: to, t: 0.5)

        XCTAssertEqual(first, second, "Interpolation must be deterministic")
        assertPoint(first.translation, pt(60, 120))
        // Log-space zoom interpolates to the geometric mean.
        XCTAssertEqual(first.zoom, 2, accuracy: 1e-12)
    }

    // MARK: Pixel alignment

    func testPixelAlignedRoundsTranslationOnly() {
        let transform = CanvasTransform(translation: pt(10.31, -7.69), zoom: 2.75)
        let aligned = transform.pixelAligned()
        assertPoint(aligned.translation, pt(10.5, -7.5))
        XCTAssertEqual(aligned.zoom, transform.zoom)
    }

    func testPixelAlignedUsesRequestedScale() {
        let transform = CanvasTransform(translation: pt(10.31, -7.69), zoom: 1)
        assertPoint(transform.pixelAligned(scale: 1).translation, pt(10, -8))
        assertPoint(transform.pixelAligned(scale: 0.5).translation, pt(10, -8))
    }

    func testPixelAlignedWithZeroScaleIsNoOp() {
        // Guarded in `pixelAligned` so callers cannot divide by zero.
        let transform = CanvasTransform(translation: pt(10.31, -7.69), zoom: 1)
        XCTAssertEqual(transform.pixelAligned(scale: 0), transform)
    }

    // MARK: Convenience

    func testPanningAddsScreenDelta() {
        let transform = CanvasTransform(translation: pt(10, 20), zoom: 2)
        let panned = transform.panning(by: pt(-5, 15))
        assertPoint(panned.translation, pt(5, 35))
        XCTAssertEqual(panned.zoom, 2)
    }

    func testZoomPercentage() {
        XCTAssertEqual(CanvasTransform(zoom: 0.333).zoomPercentage, 33)
        XCTAssertEqual(CanvasTransform(zoom: 1).zoomPercentage, 100)
        XCTAssertEqual(CanvasTransform(zoom: 12).zoomPercentage, 1200)
    }
}
