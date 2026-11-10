import Foundation

// MARK: - Plane model
//
// In canvas mode every real window gets a rectangle on a single plane. Plane
// units are screen points at 100% zoom, with the origin at the top-left of the
// primary display — so a window's original frame is already a valid plane rect
// and no conversion is needed at enter time.
//
// The camera then maps plane space to screen space exactly like the board
// canvas: `screen = plane * zoom + translation`.

public struct PlaneWindow: Codable, Hashable, Sendable, Identifiable {
    /// Stable identity across launches: bundle id plus a normalised title.
    public var id: String
    public var windowNumber: UInt32
    public var ownerPID: Int32
    public var appName: String
    public var title: String
    public var bundleIdentifier: String?
    public var planeFrame: CanvasRect
    /// The frame the window had before canvas mode started, used to restore.
    public var originalFrame: CanvasRect
    public var isMinimized: Bool

    public init(
        id: String,
        windowNumber: UInt32,
        ownerPID: Int32,
        appName: String,
        title: String,
        bundleIdentifier: String?,
        planeFrame: CanvasRect,
        originalFrame: CanvasRect,
        isMinimized: Bool = false
    ) {
        self.id = id
        self.windowNumber = windowNumber
        self.ownerPID = ownerPID
        self.appName = appName
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.planeFrame = planeFrame
        self.originalFrame = originalFrame
        self.isMinimized = isMinimized
    }

    public var displayLabel: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    public static func identityKey(bundleIdentifier: String?, appName: String, title: String) -> String {
        let normalised = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\u{2014}", with: "-")
        return "\(bundleIdentifier ?? appName)|\(normalised)"
    }
}

public struct PlaneLayout: Codable, Hashable, Sendable {
    public var camera: CanvasTransform
    public var windows: [PlaneWindow]
    public var savedAt: Date

    public init(camera: CanvasTransform = .identity, windows: [PlaneWindow] = [], savedAt: Date = Date()) {
        self.camera = camera
        self.windows = windows
        self.savedAt = savedAt
    }

    public var bounds: CanvasRect? {
        CanvasRect.bounding(windows.map(\.planeFrame))
    }
}

// MARK: - Tiling

public enum TileZone: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case fill

    /// Zone detected for a drop point inside a rect, with a dead zone in the
    /// middle so ordinary drags do not tile by accident.
    public static func zone(for point: CanvasPoint, in rect: CanvasRect, edgeFraction: Double = 0.18) -> TileZone? {
        guard rect.width > 1, rect.height > 1 else { return nil }
        let relativeX = (point.x - rect.minX) / rect.width
        let relativeY = (point.y - rect.minY) / rect.height
        let nearLeft = relativeX < edgeFraction
        let nearRight = relativeX > 1 - edgeFraction
        let nearTop = relativeY < edgeFraction
        let nearBottom = relativeY > 1 - edgeFraction

        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return nil
        }
    }

    public func frame(in area: CanvasRect, gap: Double = 12) -> CanvasRect {
        let halfWidth = (area.width - gap * 3) / 2
        let halfHeight = (area.height - gap * 3) / 2
        switch self {
        case .left:
            return CanvasRect(x: area.minX + gap, y: area.minY + gap, width: halfWidth, height: area.height - gap * 2)
        case .right:
            return CanvasRect(x: area.midX + gap / 2, y: area.minY + gap, width: halfWidth, height: area.height - gap * 2)
        case .top:
            return CanvasRect(x: area.minX + gap, y: area.minY + gap, width: area.width - gap * 2, height: halfHeight)
        case .bottom:
            return CanvasRect(x: area.minX + gap, y: area.midY + gap / 2, width: area.width - gap * 2, height: halfHeight)
        case .topLeft:
            return CanvasRect(x: area.minX + gap, y: area.minY + gap, width: halfWidth, height: halfHeight)
        case .topRight:
            return CanvasRect(x: area.midX + gap / 2, y: area.minY + gap, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CanvasRect(x: area.minX + gap, y: area.midY + gap / 2, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CanvasRect(x: area.midX + gap / 2, y: area.midY + gap / 2, width: halfWidth, height: halfHeight)
        case .fill:
            return area.insetBy(gap)
        }
    }
}

// MARK: - Layout engine

public enum PlaneLayoutEngine {

    /// Zoom at which every window fits the screen with breathing room.
    /// Window managers cannot shrink a window below its app's minimum size, so
    /// the camera is clamped to `minimumZoom` rather than to zero.
    public static func fittingZoom(
        for bounds: CanvasRect,
        in screen: CanvasRect,
        padding: Double = 64,
        minimumZoom: Double = 0.34,
        maximumZoom: Double = 1.0
    ) -> Double {
        guard bounds.width > 1, bounds.height > 1 else { return 1 }
        let availableWidth = max(1, screen.width - padding * 2)
        let availableHeight = max(1, screen.height - padding * 2)
        let scale = min(availableWidth / bounds.width, availableHeight / bounds.height)
        return Geometry.clamp(scale, minimumZoom, maximumZoom)
    }

    /// Camera that centres `bounds` in `screen` at `zoom`.
    public static func camera(fitting bounds: CanvasRect, in screen: CanvasRect, zoom: Double) -> CanvasTransform {
        CanvasTransform(
            translation: CanvasPoint(
                x: screen.midX - bounds.center.x * zoom,
                y: screen.midY - bounds.center.y * zoom
            ),
            zoom: zoom
        )
    }

    /// Camera that puts `frame` at `scale` in the middle of the screen.
    public static func camera(focusing frame: CanvasRect, in screen: CanvasRect, scale: Double = 1) -> CanvasTransform {
        CanvasTransform(
            translation: CanvasPoint(
                x: screen.midX - frame.center.x * scale,
                y: screen.midY - frame.center.y * scale
            ),
            zoom: scale
        )
    }

    /// Initial plane layout: keep the desktop's arrangement, but pull windows in
    /// so the cluster is roughly centred and not trailing off-screen.
    public static func normalise(frames: [CanvasRect], into screen: CanvasRect, padding: Double = 40) -> [CanvasRect] {
        guard let union = CanvasRect.bounding(frames), !union.isEmpty else { return frames }
        let available = screen.insetBy(padding)
        // Only move the cluster; do not rescale here — zoom does the scaling.
        var offset = CanvasPoint(x: available.midX - union.center.x, y: available.midY - union.center.y)
        // If the cluster is wider than the screen even at minimum zoom, leave it
        // where it is so windows keep their relative relationship.
        if union.width > available.width * 3 || union.height > available.height * 3 {
            offset = .zero
        }
        return frames.map { $0.offsetBy(offset) }
    }

    /// Places a window onto a stack: offset from the target, clamped so it stays
    /// visible.
    public static func stacked(_ frame: CanvasRect, onto target: CanvasRect, offset: Double = 26) -> CanvasRect {
        CanvasRect(x: target.minX + offset, y: target.minY + offset, width: frame.width, height: frame.height)
    }

    /// Picks a free slot to the right of the current bounds for a new window.
    public static func parkingSpot(for size: CanvasSize, avoiding occupied: [CanvasRect], spacing: Double = 32) -> CanvasRect {
        guard let union = CanvasRect.bounding(occupied) else {
            return CanvasRect(origin: .zero, size: size)
        }
        return CanvasRect(x: union.maxX + spacing, y: union.minY, width: size.width, height: size.height)
    }

    /// Nearest window in a direction from a reference frame, used by arrow keys.
    public static func nearest(to reference: CanvasRect, in frames: [String: CanvasRect], direction: Direction) -> String? {
        var best: (String, Double)?
        let referenceCenter = reference.center
        for (id, frame) in frames {
            let center = frame.center
            let dx = center.x - referenceCenter.x
            let dy = center.y - referenceCenter.y
            let isCandidate: Bool
            let distance: Double
            switch direction {
            case .left:
                isCandidate = dx < -1
                distance = abs(dx) + abs(dy) * 0.5
            case .right:
                isCandidate = dx > 1
                distance = abs(dx) + abs(dy) * 0.5
            case .up:
                isCandidate = dy < -1
                distance = abs(dy) + abs(dx) * 0.5
            case .down:
                isCandidate = dy > 1
                distance = abs(dy) + abs(dx) * 0.5
            }
            guard isCandidate else { continue }
            if best == nil || distance < best!.1 {
                best = (id, distance)
            }
        }
        return best?.0
    }

    public enum Direction: String, Sendable {
        case left, right, up, down
    }
}
