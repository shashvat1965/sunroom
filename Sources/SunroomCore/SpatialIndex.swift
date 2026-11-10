import Foundation

/// A uniform-grid spatial index over node rectangles.
///
/// An infinite canvas can hold tens of thousands of nodes; the editor only ever
/// needs the ones inside the viewport. Cell size is a power-of-two-ish constant
/// tuned for typical note sizes so each node lands in one or two cells.
///
/// Rectangles that would span more than `maxCellsPerRect` cells (a group frame
/// dragged across a continent, for example) are kept in a small oversized list
/// and tested directly. Without that list they would be registered in a single
/// cell and become invisible to queries over the rest of their area.
public struct SpatialIndex: Sendable {
    public struct Entry: Sendable {
        public let id: UUID
        public var rect: CanvasRect
    }

    public let cellSize: Double
    private var cells: [CellKey: Set<UUID>] = [:]
    private var rects: [UUID: CanvasRect] = [:]
    private var oversized: [UUID: CanvasRect] = [:]
    private var contentBounds: CanvasRect?

    struct CellKey: Hashable, Sendable {
        let x: Int
        let y: Int
    }

    private static let maxCellsPerRect = 4096

    public init(cellSize: Double = 512) {
        self.cellSize = max(16, cellSize)
    }

    public var count: Int { rects.count }

    public var isEmpty: Bool { rects.isEmpty }

    /// Bounds of everything indexed, or nil when empty. Maintained on insert
    /// and recomputed lazily after removals.
    public var bounds: CanvasRect? { contentBounds }

    // MARK: Mutation

    public mutating func insert(id: UUID, rect: CanvasRect) {
        remove(id: id)
        let standardized = rect.standardized
        rects[id] = standardized

        if cellSpan(for: standardized) > Self.maxCellsPerRect {
            oversized[id] = standardized
        } else {
            for key in cellKeys(for: standardized) {
                cells[key, default: []].insert(id)
            }
        }
        contentBounds = contentBounds.map { $0.union(standardized) } ?? standardized
    }

    public mutating func remove(id: UUID) {
        guard let existing = rects.removeValue(forKey: id) else { return }
        oversized.removeValue(forKey: id)
        for key in cellKeys(for: existing) {
            guard var bucket = cells[key] else { continue }
            bucket.remove(id)
            if bucket.isEmpty {
                cells.removeValue(forKey: key)
            } else {
                cells[key] = bucket
            }
        }
        if let bounds = contentBounds, !bounds.encloses(existing) {
            // The removed rect was not on the boundary; nothing to do.
        } else {
            contentBounds = nil
        }
    }

    public mutating func removeAll() {
        cells.removeAll(keepingCapacity: true)
        rects.removeAll(keepingCapacity: true)
        oversized.removeAll(keepingCapacity: true)
        contentBounds = nil
    }

    public mutating func rebuild(from entries: [Entry]) {
        removeAll()
        for entry in entries {
            insert(id: entry.id, rect: entry.rect)
        }
    }

    // MARK: Queries

    public func rect(for id: UUID) -> CanvasRect? {
        rects[id]
    }

    /// All ids whose bounds intersect `rect`. A node larger than the query rect
    /// but overlapping it is still returned.
    public func ids(intersecting rect: CanvasRect) -> Set<UUID> {
        let standardized = rect.standardized
        var result: Set<UUID> = []
        if cellSpan(for: standardized) > Self.maxCellsPerRect {
            // A query larger than the grid (export bounds, "select everything
            // visible" on a huge canvas): test every rect directly.
            for (id, candidate) in rects where candidate.intersects(standardized) {
                result.insert(id)
            }
            return result
        }
        for key in cellKeys(for: standardized) {
            guard let bucket = cells[key] else { continue }
            for id in bucket {
                guard let candidate = rects[id] else { continue }
                if candidate.intersects(standardized) {
                    result.insert(id)
                }
            }
        }
        for (id, candidate) in oversized where candidate.intersects(standardized) {
            result.insert(id)
        }
        return result
    }

    public func ids(in rect: CanvasRect) -> [UUID] {
        ids(intersecting: rect).sorted()
    }

    /// Ids whose rect contains `point`.
    public func ids(containing point: CanvasPoint) -> Set<UUID> {
        var result: Set<UUID> = []
        for id in ids(intersecting: CanvasRect(x: point.x, y: point.y, width: 0, height: 0)) {
            if let candidate = rects[id], candidate.contains(point) {
                result.insert(id)
            }
        }
        return result
    }

    /// Candidate ids within `distance` of `point`, sorted by distance.
    ///
    /// An infinite `maxDistance` scans every indexed rect instead of building a
    /// gigantic probe rectangle — the probe would overflow the cell arithmetic
    /// and trap.
    public func nearest(to point: CanvasPoint, limit: Int = 1, maxDistance: Double = .infinity) -> [UUID] {
        var candidates: [UUID]
        if maxDistance.isFinite, maxDistance >= 0 {
            let probe = CanvasRect(
                x: point.x - maxDistance,
                y: point.y - maxDistance,
                width: maxDistance * 2,
                height: maxDistance * 2
            )
            candidates = Array(ids(intersecting: probe))
        } else {
            candidates = Array(rects.keys)
        }

        var scored: [(UUID, Double)] = []
        scored.reserveCapacity(candidates.count)
        for id in candidates {
            guard let candidate = rects[id] else { continue }
            let distance = Geometry.distance(from: point, to: candidate)
            guard distance <= maxDistance else { continue }
            scored.append((id, distance))
        }
        return scored.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.uuidString < rhs.0.uuidString : lhs.1 < rhs.1
        }.prefix(limit).map(\.0)
    }

    /// All ids in the index, useful for exports and tests.
    public var allIDs: [UUID] { Array(rects.keys) }

    /// Number of grid cells a rect touches, saturating instead of overflowing.
    private func cellSpan(for rect: CanvasRect) -> Int {
        let dx = Int(floor(rect.maxX / cellSize)) - Int(floor(rect.minX / cellSize))
        let dy = Int(floor(rect.maxY / cellSize)) - Int(floor(rect.minY / cellSize))
        guard dx >= 0, dy >= 0 else { return Int.max }
        guard dx < 1_000_000, dy < 1_000_000 else { return Int.max }
        let (product, overflow) = (dx + 1).multipliedReportingOverflow(by: dy + 1)
        return overflow ? Int.max : product
    }

    private func cellKeys(for rect: CanvasRect) -> Set<CellKey> {
        let minCellX = Int(floor(rect.minX / cellSize))
        let minCellY = Int(floor(rect.minY / cellSize))
        let maxCellX = Int(floor(rect.maxX / cellSize))
        let maxCellY = Int(floor(rect.maxY / cellSize))
        guard cellSpan(for: rect) <= Self.maxCellsPerRect else { return [] }
        var keys: Set<CellKey> = []
        for x in minCellX...maxCellX {
            for y in minCellY...maxCellY {
                keys.insert(CellKey(x: x, y: y))
            }
        }
        return keys
    }
}
