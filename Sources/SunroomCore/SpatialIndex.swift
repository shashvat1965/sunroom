import Foundation

/// A uniform-grid spatial index over node rectangles.
///
/// An infinite canvas can hold tens of thousands of nodes; the editor only ever
/// needs the ones inside the viewport. Cell size is a power-of-two-ish constant
/// tuned for typical note sizes so each node lands in one or two cells.
public struct SpatialIndex: Sendable {
    public struct Entry: Sendable {
        public let id: UUID
        public var rect: CanvasRect
    }

    public let cellSize: Double
    private var cells: [CellKey: Set<UUID>] = [:]
    private var rects: [UUID: CanvasRect] = [:]

    struct CellKey: Hashable, Sendable {
        let x: Int
        let y: Int
    }

    public init(cellSize: Double = 512) {
        self.cellSize = max(16, cellSize)
    }

    public var count: Int { rects.count }

    public var isEmpty: Bool { rects.isEmpty }

    // MARK: Mutation

    public mutating func insert(id: UUID, rect: CanvasRect) {
        remove(id: id)
        let standardized = rect.standardized
        rects[id] = standardized
        for key in cellKeys(for: standardized) {
            cells[key, default: []].insert(id)
        }
    }

    public mutating func remove(id: UUID) {
        guard let existing = rects.removeValue(forKey: id) else { return }
        for key in cellKeys(for: existing) {
            guard var bucket = cells[key] else { continue }
            bucket.remove(id)
            if bucket.isEmpty {
                cells.removeValue(forKey: key)
            } else {
                cells[key] = bucket
            }
        }
    }

    public mutating func removeAll() {
        cells.removeAll(keepingCapacity: true)
        rects.removeAll(keepingCapacity: true)
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
        for key in cellKeys(for: standardized) {
            guard let bucket = cells[key] else { continue }
            for id in bucket {
                guard let candidate = rects[id] else { continue }
                if candidate.intersects(standardized) {
                    result.insert(id)
                }
            }
        }
        return result
    }

    public func ids(in rect: CanvasRect) -> [UUID] {
        ids(intersecting: rect).sorted()
    }

    /// Ids whose rect contains `point`, ordered by ascending z is the caller's job.
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
    public func nearest(to point: CanvasPoint, limit: Int = 1, maxDistance: Double = .infinity) -> [UUID] {
        var scored: [(UUID, Double)] = []
        let probe = CanvasRect(x: point.x - maxDistance, y: point.y - maxDistance, width: maxDistance * 2, height: maxDistance * 2)
        let probeRect = maxDistance.isFinite ? probe : CanvasRect(x: -1e12, y: -1e12, width: 2e12, height: 2e12)
        for id in ids(intersecting: probeRect) {
            guard let candidate = rects[id] else { continue }
            let distance = Geometry.distance(from: point, to: candidate)
            guard distance <= maxDistance else { continue }
            scored.append((id, distance))
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    /// All ids in the index, useful for exports and tests.
    public var allIDs: [UUID] { Array(rects.keys) }

    private func cellKeys(for rect: CanvasRect) -> Set<CellKey> {
        let minCellX = Int(floor(rect.minX / cellSize))
        let minCellY = Int(floor(rect.minY / cellSize))
        let maxCellX = Int(floor(rect.maxX / cellSize))
        let maxCellY = Int(floor(rect.maxY / cellSize))
        var keys: Set<CellKey> = []
        // Guard against absurd rects (e.g. a group dragged to 1e9) exploding the grid.
        guard (maxCellX - minCellX) * (maxCellY - minCellY) < 4096 else {
            return [CellKey(x: minCellX, y: minCellY)]
        }
        for x in minCellX...maxCellX {
            for y in minCellY...maxCellY {
                keys.insert(CellKey(x: x, y: y))
            }
        }
        return keys
    }
}
