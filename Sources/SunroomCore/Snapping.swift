import Foundation

/// A guide line drawn while dragging, in canvas space.
public struct SnapGuide: Hashable, Sendable {
    public enum Orientation: String, Sendable {
        case vertical
        case horizontal
    }

    public var orientation: Orientation
    /// For `.vertical`, the x position. For `.horizontal`, the y position.
    public var position: Double
    public var start: Double
    public var end: Double

    public init(orientation: Orientation, position: Double, start: Double, end: Double) {
        self.orientation = orientation
        self.position = position
        self.start = start
        self.end = end
    }
}

public struct SnapConfiguration: Hashable, Sendable {
    /// Snap distance in canvas points. Callers divide by zoom so the pull feels
    /// constant on screen no matter how far out you are.
    public var tolerance: Double
    public var snapToGrid: Bool
    public var gridSpacing: Double
    public var snapToEdges: Bool
    public var snapToCenters: Bool

    public init(
        tolerance: Double = 6,
        snapToGrid: Bool = false,
        gridSpacing: Double = 48,
        snapToEdges: Bool = true,
        snapToCenters: Bool = true
    ) {
        self.tolerance = tolerance
        self.snapToGrid = snapToGrid
        self.gridSpacing = max(1, gridSpacing)
        self.snapToEdges = snapToEdges
        self.snapToCenters = snapToCenters
    }

    public static let `default` = SnapConfiguration()
    public static let disabled = SnapConfiguration(tolerance: 0, snapToGrid: false, snapToEdges: false, snapToCenters: false)

    /// Scales tolerance so it stays constant in screen points.
    public func scaled(forZoom zoom: Double) -> SnapConfiguration {
        var copy = self
        copy.tolerance = tolerance / max(zoom, 0.0001)
        return copy
    }
}

public struct SnapResult: Hashable, Sendable {
    public var adjustedOrigin: CanvasPoint
    public var guides: [SnapGuide]
    public var snappedHorizontally: Bool
    public var snappedVertically: Bool

    public init(adjustedOrigin: CanvasPoint, guides: [SnapGuide] = [], snappedHorizontally: Bool = false, snappedVertically: Bool = false) {
        self.adjustedOrigin = adjustedOrigin
        self.guides = guides
        self.snappedHorizontally = snappedHorizontally
        self.snappedVertically = snappedVertically
    }

    public var didSnap: Bool { snappedHorizontally || snappedVertically }
}

public enum Snapping {
    public struct AxisCandidate {
        public let delta: Double
        public let line: Double
        public let spanStart: Double
        public let spanEnd: Double
    }

    /// Snaps a moving rect against static target rects.
    ///
    /// X and Y are solved independently, which is what makes corner snapping
    /// feel right: you can align the left edge while also centering vertically.
    public static func snap(rect: CanvasRect, targets: [CanvasRect], configuration: SnapConfiguration = .default) -> SnapResult {
        let moving = rect.standardized
        guard configuration.tolerance > 0, !targets.isEmpty || configuration.snapToGrid else {
            return SnapResult(adjustedOrigin: moving.origin)
        }

        var bestX: AxisCandidate?
        var bestY: AxisCandidate?

        func considerX(delta: Double, line: Double, spanStart: Double, spanEnd: Double) {
            guard abs(delta) <= configuration.tolerance else { return }
            if let current = bestX, abs(current.delta) <= abs(delta) { return }
            bestX = AxisCandidate(delta: delta, line: line, spanStart: spanStart, spanEnd: spanEnd)
        }

        func considerY(delta: Double, line: Double, spanStart: Double, spanEnd: Double) {
            guard abs(delta) <= configuration.tolerance else { return }
            if let current = bestY, abs(current.delta) <= abs(delta) { return }
            bestY = AxisCandidate(delta: delta, line: line, spanStart: spanStart, spanEnd: spanEnd)
        }

        let movingEdgesX: [Double] = configuration.snapToEdges ? [moving.minX, moving.maxX] : []
        let movingEdgesY: [Double] = configuration.snapToEdges ? [moving.minY, moving.maxY] : []
        let movingCenterX = moving.center.x
        let movingCenterY = moving.center.y

        for target in targets {
            let standardized = target.standardized
            if configuration.snapToEdges {
                for movingEdge in movingEdgesX {
                    for targetEdge in [standardized.minX, standardized.maxX] {
                        let delta = targetEdge - movingEdge
                        let spanStart = min(standardized.minY, moving.minY)
                        let spanEnd = max(standardized.maxY, moving.maxY)
                        considerX(delta: delta, line: targetEdge, spanStart: spanStart, spanEnd: spanEnd)
                    }
                }
                for movingEdge in movingEdgesY {
                    for targetEdge in [standardized.minY, standardized.maxY] {
                        let delta = targetEdge - movingEdge
                        let spanStart = min(standardized.minX, moving.minX)
                        let spanEnd = max(standardized.maxX, moving.maxX)
                        considerY(delta: delta, line: targetEdge, spanStart: spanStart, spanEnd: spanEnd)
                    }
                }
            }
            if configuration.snapToCenters {
                considerX(
                    delta: standardized.center.x - movingCenterX,
                    line: standardized.center.x,
                    spanStart: min(standardized.minY, moving.minY),
                    spanEnd: max(standardized.maxY, moving.maxY)
                )
                considerY(
                    delta: standardized.center.y - movingCenterY,
                    line: standardized.center.y,
                    spanStart: min(standardized.minX, moving.minX),
                    spanEnd: max(standardized.maxX, moving.maxX)
                )
            }
        }

        if configuration.snapToGrid, bestX == nil || bestY == nil {
            let spacing = configuration.gridSpacing
            let gridX = (moving.minX / spacing).rounded() * spacing
            let gridY = (moving.minY / spacing).rounded() * spacing
            if bestX == nil, abs(gridX - moving.minX) <= configuration.tolerance {
                bestX = AxisCandidate(delta: gridX - moving.minX, line: gridX, spanStart: moving.minY, spanEnd: moving.maxY)
            }
            if bestY == nil, abs(gridY - moving.minY) <= configuration.tolerance {
                bestY = AxisCandidate(delta: gridY - moving.minY, line: gridY, spanStart: moving.minX, spanEnd: moving.maxX)
            }
        }

        var origin = moving.origin
        var guides: [SnapGuide] = []
        if let bestX {
            origin.x += bestX.delta
            guides.append(
                SnapGuide(
                    orientation: .vertical,
                    position: bestX.line,
                    start: min(bestX.spanStart, bestX.spanEnd),
                    end: max(bestX.spanStart, bestX.spanEnd)
                )
            )
        }
        if let bestY {
            origin.y += bestY.delta
            guides.append(
                SnapGuide(
                    orientation: .horizontal,
                    position: bestY.line,
                    start: min(bestY.spanStart, bestY.spanEnd),
                    end: max(bestY.spanStart, bestY.spanEnd)
                )
            )
        }

        return SnapResult(
            adjustedOrigin: origin,
            guides: guides,
            snappedHorizontally: bestX != nil,
            snappedVertically: bestY != nil
        )
    }

    /// Snaps a multi-selection: the selection's bounding box snaps as one unit.
    public static func snap(bounds: CanvasRect, targets: [CanvasRect], configuration: SnapConfiguration = .default) -> SnapResult {
        snap(rect: bounds, targets: targets, configuration: configuration)
    }

    /// Computes alignment guides (edges and centers) between two rects, used to
    /// draw persistent guides while a selection is active.
    public static func alignmentGuides(between a: CanvasRect, and b: CanvasRect, tolerance: Double = 0.5) -> [SnapGuide] {
        var guides: [SnapGuide] = []
        let pairs: [(Double, Double, SnapGuide.Orientation)] = [
            (a.minX, b.minX, .vertical),
            (a.minX, b.maxX, .vertical),
            (a.maxX, b.minX, .vertical),
            (a.maxX, b.maxX, .vertical),
            (a.center.x, b.center.x, .vertical),
            (a.minY, b.minY, .horizontal),
            (a.minY, b.maxY, .horizontal),
            (a.maxY, b.minY, .horizontal),
            (a.maxY, b.maxY, .horizontal),
            (a.center.y, b.center.y, .horizontal),
        ]
        for (lhs, rhs, orientation) in pairs where abs(lhs - rhs) <= tolerance {
            let start = orientation == .vertical ? min(a.minY, b.minY) : min(a.minX, b.minX)
            let end = orientation == .vertical ? max(a.maxY, b.maxY) : max(a.maxX, b.maxX)
            guides.append(SnapGuide(orientation: orientation, position: rhs, start: start, end: end))
        }
        return guides
    }
}
