import Foundation
import CoreGraphics

/// The camera over an infinite canvas.
///
/// Mapping is `screen = canvas * zoom + translation`, where both `screen` and
/// `translation` are in the view's coordinate space (points, origin top-left).
public struct CanvasTransform: Codable, Hashable, Sendable {
    public static let minZoom: Double = 0.02
    public static let maxZoom: Double = 12.0

    /// Screen-space translation of the canvas origin.
    public var translation: CanvasPoint
    /// Scale factor, always clamped into `[minZoom, maxZoom]`.
    public var zoom: Double

    public init(translation: CanvasPoint = .zero, zoom: Double = 1) {
        self.translation = translation
        self.zoom = Geometry.clamp(zoom, Self.minZoom, Self.maxZoom)
    }

    public static let identity = CanvasTransform()

    // MARK: Mapping

    public func screenPoint(fromCanvas point: CanvasPoint) -> CanvasPoint {
        CanvasPoint(x: point.x * zoom + translation.x, y: point.y * zoom + translation.y)
    }

    public func canvasPoint(fromScreen point: CanvasPoint) -> CanvasPoint {
        CanvasPoint(x: (point.x - translation.x) / zoom, y: (point.y - translation.y) / zoom)
    }

    public func screenRect(fromCanvas rect: CanvasRect) -> CanvasRect {
        CanvasRect(origin: screenPoint(fromCanvas: rect.origin), size: CanvasSize(width: rect.width * zoom, height: rect.height * zoom))
    }

    public func canvasRect(fromScreen rect: CanvasRect) -> CanvasRect {
        CanvasRect(
            origin: canvasPoint(fromScreen: rect.origin),
            size: CanvasSize(width: rect.width / zoom, height: rect.height / zoom)
        )
    }

    public func screenDistance(fromCanvas distance: Double) -> Double {
        distance * zoom
    }

    public func canvasDistance(fromScreen distance: Double) -> Double {
        distance / zoom
    }

    // MARK: Camera moves

    /// Pans by a screen-space delta.
    public func panning(by delta: CanvasPoint) -> CanvasTransform {
        var copy = self
        copy.translation = translation + delta
        return copy
    }

    /// Zooms to `targetZoom`, keeping the canvas point under `anchor` (a
    /// screen-space point) fixed on screen. This is the behavior people expect
    /// from trackpad pinch and ⌘-scroll.
    public func zooming(to targetZoom: Double, anchor: CanvasPoint) -> CanvasTransform {
        let clamped = Geometry.clamp(targetZoom, Self.minZoom, Self.maxZoom)
        guard clamped != zoom else { return self }
        let anchorInCanvas = canvasPoint(fromScreen: anchor)
        var copy = self
        copy.zoom = clamped
        copy.translation = CanvasPoint(
            x: anchor.x - anchorInCanvas.x * clamped,
            y: anchor.y - anchorInCanvas.y * clamped
        )
        return copy
    }

    public func zooming(by factor: Double, anchor: CanvasPoint) -> CanvasTransform {
        guard factor > 0 else { return self }
        return zooming(to: zoom * factor, anchor: anchor)
    }

    /// Centers `rect` in a viewport of `viewportSize`, scaling so it fits with
    /// `padding` screen points of breathing room. Never zooms past 1.0, so
    /// "fit" on a small selection does not blow it up to absurd size.
    public func fitting(_ rect: CanvasRect, in viewportSize: CanvasSize, padding: Double = 64, maxZoom: Double = 1.0) -> CanvasTransform {
        guard rect.width > 0, rect.height > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return centering(on: rect.center, in: viewportSize)
        }
        let availableWidth = max(1, viewportSize.width - padding * 2)
        let availableHeight = max(1, viewportSize.height - padding * 2)
        let scale = min(availableWidth / rect.width, availableHeight / rect.height)
        let clamped = Geometry.clamp(min(scale, maxZoom), Self.minZoom, Self.maxZoom)
        let center = rect.center
        return CanvasTransform(
            translation: CanvasPoint(
                x: viewportSize.width / 2 - center.x * clamped,
                y: viewportSize.height / 2 - center.y * clamped
            ),
            zoom: clamped
        )
    }

    /// Keeps zoom, moves the camera so `point` sits at the viewport center.
    public func centering(on point: CanvasPoint, in viewportSize: CanvasSize) -> CanvasTransform {
        CanvasTransform(
            translation: CanvasPoint(
                x: viewportSize.width / 2 - point.x * zoom,
                y: viewportSize.height / 2 - point.y * zoom
            ),
            zoom: zoom
        )
    }

    /// The canvas-space rectangle currently visible in the viewport.
    public func visibleCanvasRect(in viewportSize: CanvasSize) -> CanvasRect {
        canvasRect(fromScreen: CanvasRect(x: 0, y: 0, width: viewportSize.width, height: viewportSize.height))
    }

    /// Rounds translation to whole pixels to keep text crisp at rest.
    public func pixelAligned(scale: Double = 2) -> CanvasTransform {
        guard scale > 0 else { return self }
        var copy = self
        copy.translation = translation.rounded(to: 1 / scale)
        return copy
    }

    // MARK: Convenience

    public var zoomPercentage: Int { Int((zoom * 100).rounded()) }

    public static func == (lhs: CanvasTransform, rhs: CanvasTransform) -> Bool {
        lhs.translation == rhs.translation && lhs.zoom == rhs.zoom
    }

    /// Deterministic interpolation used by camera animations and tests.
    public static func interpolate(from: CanvasTransform, to: CanvasTransform, t: Double) -> CanvasTransform {
        let clamped = Geometry.clamp(t, 0, 1)
        // Interpolate in log space so zoom feels linear to the eye.
        let startLog = log(from.zoom)
        let endLog = log(to.zoom)
        let zoom = exp(startLog + (endLog - startLog) * clamped)
        return CanvasTransform(
            translation: CanvasPoint(
                x: from.translation.x + (to.translation.x - from.translation.x) * clamped,
                y: from.translation.y + (to.translation.y - from.translation.y) * clamped
            ),
            zoom: zoom
        )
    }
}
