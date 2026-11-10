import Foundation

/// Deterministic layout routines used by "Arrange", "Tidy up" and the initial
/// demo canvas.
public enum LayoutEngine {

    public enum Arrangement: String, CaseIterable, Sendable {
        case grid
        case rows
        case columns
        case radial

        public var displayName: String {
            switch self {
            case .grid: return "Grid"
            case .rows: return "Rows"
            case .columns: return "Columns"
            case .radial: return "Radial"
            }
        }
    }

    /// Lays out rects in a roughly square grid, preserving input order.
    /// Returns frames in the same order as the input.
    public static func grid(
        sizes: [CanvasSize],
        origin: CanvasPoint = .zero,
        spacing: Double = 40,
        columns: Int? = nil
    ) -> [CanvasRect] {
        guard !sizes.isEmpty else { return [] }
        let columnCount = max(1, columns ?? Int(ceil(Double(sizes.count).squareRoot())))
        var rects: [CanvasRect] = []
        rects.reserveCapacity(sizes.count)
        var cursorY = origin.y
        var index = 0
        while index < sizes.count {
            let row = Array(sizes[index..<min(index + columnCount, sizes.count)])
            let rowHeight = row.map(\.height).max() ?? 0
            var cursorX = origin.x
            for size in row {
                rects.append(CanvasRect(x: cursorX, y: cursorY, width: size.width, height: size.height))
                cursorX += size.width + spacing
            }
            cursorY += rowHeight + spacing
            index += columnCount
        }
        return rects
    }

    /// Stacks rects in a single row, top-aligned.
    public static func rows(sizes: [CanvasSize], origin: CanvasPoint = .zero, spacing: Double = 40) -> [CanvasRect] {
        var cursorX = origin.x
        return sizes.map { size in
            defer { cursorX += size.width + spacing }
            return CanvasRect(x: cursorX, y: origin.y, width: size.width, height: size.height)
        }
    }

    /// Stacks rects in a single column, leading-aligned.
    public static func columns(sizes: [CanvasSize], origin: CanvasPoint = .zero, spacing: Double = 40) -> [CanvasRect] {
        var cursorY = origin.y
        return sizes.map { size in
            defer { cursorY += size.height + spacing }
            return CanvasRect(x: origin.x, y: cursorY, width: size.width, height: size.height)
        }
    }

    /// Places rects evenly around a circle, sized to the largest item.
    public static func radial(sizes: [CanvasSize], center: CanvasPoint = .zero, radius: Double? = nil) -> [CanvasRect] {
        guard !sizes.isEmpty else { return [] }
        let maxDimension = sizes.map { max($0.width, $0.height) }.max() ?? 100
        let effectiveRadius = radius ?? max(maxDimension * 1.1, Double(sizes.count) * maxDimension / (2 * .pi))
        return sizes.enumerated().map { index, size in
            let angle = (Double(index) / Double(sizes.count)) * 2 * .pi
            let point = CanvasPoint(
                x: center.x + cos(angle) * effectiveRadius - size.width / 2,
                y: center.y + sin(angle) * effectiveRadius - size.height / 2
            )
            return CanvasRect(origin: point, size: size)
        }
    }

    public static func arrange(
        sizes: [CanvasSize],
        mode: Arrangement,
        origin: CanvasPoint = .zero,
        spacing: Double = 40
    ) -> [CanvasRect] {
        switch mode {
        case .grid: return grid(sizes: sizes, origin: origin, spacing: spacing)
        case .rows: return rows(sizes: sizes, origin: origin, spacing: spacing)
        case .columns: return columns(sizes: sizes, origin: origin, spacing: spacing)
        case .radial: return radial(sizes: sizes, center: CanvasPoint(x: origin.x, y: origin.y))
        }
    }

    /// Re-flows an existing set of nodes into `mode`, keeping their visual order.
    public static func reflow(nodes: [CanvasNode], mode: Arrangement, spacing: Double = 40) -> [CanvasRect] {
        let ordered = nodes.sorted { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) > 1 {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.frame.minX < rhs.frame.minX
        }
        let origin = ordered.first?.frame.origin ?? .zero
        let frames = arrange(sizes: ordered.map(\.frame.size), mode: mode, origin: origin, spacing: spacing)
        var result: [CanvasRect] = []
        result.reserveCapacity(frames.count)
        // Map back to the input order.
        var mapping: [UUID: CanvasRect] = [:]
        for (node, frame) in zip(ordered, frames) {
            mapping[node.id] = frame
        }
        for node in nodes {
            result.append(mapping[node.id] ?? node.frame)
        }
        return result
    }

    /// Picks the tidiest arrangement for a set of sizes by minimizing the
    /// bounding box's aspect ratio deviation from the golden ratio.
    public static func bestArrangement(for sizes: [CanvasSize], spacing: Double = 40) -> Arrangement {
        guard sizes.count > 2 else { return .rows }
        let gold = 1.618
        var best: (Arrangement, Double) = (.grid, .infinity)
        for candidate in [Arrangement.grid, .rows, .columns] {
            guard let bounds = CanvasRect.bounding(arrange(sizes: sizes, mode: candidate, spacing: spacing)) else { continue }
            let ratio = bounds.width / max(bounds.height, 1)
            let score = abs(log(ratio / gold))
            if score < best.1 {
                best = (candidate, score)
            }
        }
        return best.0
    }
}

/// Picks what to render at a given zoom level. Keeps far-out views cheap and
/// legible instead of drawing unreadable 4-point text.
public enum LevelOfDetail: String, Sendable {
    /// Full fidelity: live snapshots, text, controls.
    case full
    /// Readable but simplified: titles instead of body text, no chrome.
    case compact
    /// Blocks only: color chips with a label for the largest items.
    case blocks
    /// Colored rectangles; used below ~8% zoom.
    case silhouette

    public static func forZoom(_ zoom: Double) -> LevelOfDetail {
        switch zoom {
        case ..<0.08: return .silhouette
        case ..<0.28: return .blocks
        case ..<0.62: return .compact
        default: return .full
        }
    }

    public var showsText: Bool { self == .full || self == .compact }
    public var showsSnapshots: Bool { self == .full }
    public var showsControls: Bool { self == .full }
}

/// Maps canvas space into the minimap's fixed viewport.
public struct MinimapProjection: Sendable {
    public let scale: Double
    public let offset: CanvasPoint
    public let canvasBounds: CanvasRect
    public let minimapSize: CanvasSize

    public init(canvasBounds: CanvasRect, viewport: CanvasRect, minimapSize: CanvasSize, padding: Double = 8) {
        self.canvasBounds = canvasBounds
        self.minimapSize = minimapSize
        let contentWidth = max(canvasBounds.width, 1)
        let contentHeight = max(canvasBounds.height, 1)
        let availableWidth = max(1, minimapSize.width - padding * 2)
        let availableHeight = max(1, minimapSize.height - padding * 2)
        let scale = min(availableWidth / contentWidth, availableHeight / contentHeight)
        self.scale = scale
        self.offset = CanvasPoint(
            x: padding + (availableWidth - contentWidth * scale) / 2 - canvasBounds.minX * scale,
            y: padding + (availableHeight - contentHeight * scale) / 2 - canvasBounds.minY * scale
        )
        _ = viewport
    }

    public func point(for canvasPoint: CanvasPoint) -> CanvasPoint {
        CanvasPoint(x: canvasPoint.x * scale + offset.x, y: canvasPoint.y * scale + offset.y)
    }

    public func rect(for canvasRect: CanvasRect) -> CanvasRect {
        CanvasRect(origin: point(for: canvasRect.origin), size: CanvasSize(width: canvasRect.width * scale, height: canvasRect.height * scale))
    }

    public func canvasPoint(for minimapPoint: CanvasPoint) -> CanvasPoint {
        CanvasPoint(x: (minimapPoint.x - offset.x) / scale, y: (minimapPoint.y - offset.y) / scale)
    }

    /// The bounds to use for a minimap: the document's content plus the current
    /// viewport, so the indicator never leaves the frame.
    public static func bounds(content: CanvasRect?, viewport: CanvasRect) -> CanvasRect {
        guard let content, !content.isEmpty else { return viewport }
        return content.union(viewport).insetBy(-content.width * 0.05)
    }
}
