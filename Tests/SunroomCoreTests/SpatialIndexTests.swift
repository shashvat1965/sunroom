import XCTest
@testable import SunroomCore

final class SpatialIndexTests: XCTestCase {

    // MARK: Mutation

    func testInsertAndCount() {
        var index = SpatialIndex(cellSize: 100)
        let a = UUID()
        let b = UUID()

        index.insert(id: a, rect: rect(0, 0, 50, 50))
        index.insert(id: b, rect: rect(500, 500, 50, 50))

        XCTAssertEqual(index.count, 2)
        XCTAssertFalse(index.isEmpty)
        XCTAssertEqual(index.rect(for: a), rect(0, 0, 50, 50))
        XCTAssertEqual(Set(index.allIDs), [a, b])
    }

    func testInsertStandardizesRect() {
        var index = SpatialIndex()
        let id = UUID()
        index.insert(id: id, rect: CanvasRect(origin: pt(100, 100), size: sz(-20, -30)))
        XCTAssertEqual(index.rect(for: id), rect(80, 70, 20, 30))
    }

    func testInsertingSameIDReplacesPreviousRect() {
        var index = SpatialIndex(cellSize: 100)
        let id = UUID()
        index.insert(id: id, rect: rect(0, 0, 10, 10))
        index.insert(id: id, rect: rect(1000, 1000, 10, 10))

        XCTAssertEqual(index.count, 1)
        XCTAssertTrue(index.ids(intersecting: rect(0, 0, 10, 10)).isEmpty)
        XCTAssertEqual(index.ids(intersecting: rect(1000, 1000, 10, 10)), [id])
    }

    func testRemove() {
        var index = SpatialIndex(cellSize: 100)
        let a = UUID()
        let b = UUID()
        index.insert(id: a, rect: rect(0, 0, 10, 10))
        index.insert(id: b, rect: rect(0, 0, 10, 10))

        index.remove(id: a)
        XCTAssertEqual(index.count, 1)
        XCTAssertNil(index.rect(for: a))
        XCTAssertEqual(index.ids(intersecting: rect(0, 0, 10, 10)), [b])

        index.remove(id: a) // Removing twice is harmless.
        XCTAssertEqual(index.count, 1)
    }

    func testRemoveAll() {
        var index = SpatialIndex()
        for i in 0..<10 {
            index.insert(id: UUID(), rect: rect(Double(i) * 100, 0, 50, 50))
        }
        index.removeAll()
        XCTAssertTrue(index.isEmpty)
        XCTAssertEqual(index.count, 0)
        XCTAssertTrue(index.allIDs.isEmpty)
        XCTAssertTrue(index.ids(intersecting: rect(-1e6, -1e6, 2e6, 2e6)).isEmpty)
    }

    func testRebuildReplacesContents() {
        var index = SpatialIndex(cellSize: 64)
        let stale = UUID()
        index.insert(id: stale, rect: rect(0, 0, 10, 10))

        let a = UUID()
        let b = UUID()
        index.rebuild(from: [
            .init(id: a, rect: rect(100, 100, 20, 20)),
            .init(id: b, rect: rect(300, 100, 20, 20)),
        ])

        XCTAssertEqual(index.count, 2)
        XCTAssertNil(index.rect(for: stale))
        XCTAssertEqual(index.ids(intersecting: rect(90, 90, 200, 40)), [a])
        XCTAssertEqual(index.ids(intersecting: rect(290, 90, 40, 40)), [b])
    }

    // MARK: Queries

    func testQueryReturnsOnlyIntersectingRects() {
        var index = SpatialIndex(cellSize: 100)
        let a = UUID()
        let b = UUID()
        let c = UUID()
        index.insert(id: a, rect: rect(0, 0, 10, 10))
        index.insert(id: b, rect: rect(50, 50, 10, 10))
        index.insert(id: c, rect: rect(1000, 1000, 10, 10))

        XCTAssertEqual(index.ids(intersecting: rect(0, 0, 55, 55)), [a, b])
        XCTAssertEqual(index.ids(in: rect(0, 0, 55, 55)), [a, b].sorted())
    }

    func testQueryReturnsLargeRectOverlappingSmallQuery() {
        var index = SpatialIndex(cellSize: 100)
        let huge = UUID()
        index.insert(id: huge, rect: rect(0, 0, 1_000, 1_000))

        XCTAssertEqual(index.ids(intersecting: rect(500, 500, 1, 1)), [huge])
        XCTAssertEqual(index.ids(containing: pt(750, 250)), [huge])
    }

    func testQueryOnCellBoundaries() {
        var index = SpatialIndex(cellSize: 100)
        let left = UUID()
        let right = UUID()
        index.insert(id: left, rect: rect(80, 0, 20, 100))   // 80..100, cell 0
        index.insert(id: right, rect: rect(100, 0, 50, 100)) // 100..150, cell 1

        XCTAssertEqual(index.ids(containing: pt(99.999, 50)), [left])
        XCTAssertEqual(index.ids(containing: pt(100.001, 50)), [right])
        // Rect bounds are inclusive, so a point on the shared edge is inside both.
        XCTAssertEqual(index.ids(containing: pt(100, 50)), [left, right])
        XCTAssertEqual(index.ids(containing: pt(100, 100)), [left, right])
        // A zero-width query on the boundary also touches both.
        XCTAssertEqual(index.ids(intersecting: rect(100, 0, 0, 100)), [left, right])
    }

    func testZeroSizedRectIsIndexedAndQueryable() {
        var index = SpatialIndex(cellSize: 100)
        let pointNode = UUID()
        index.insert(id: pointNode, rect: rect(100, 100, 0, 0))

        XCTAssertEqual(index.ids(containing: pt(100, 100)), [pointNode])
        XCTAssertEqual(index.ids(intersecting: rect(100, 100, 0, 0)), [pointNode])
        XCTAssertTrue(index.ids(containing: pt(100.001, 100)).isEmpty)
    }

    func testRectSpanningManyCellsIsDeduplicated() {
        var index = SpatialIndex(cellSize: 16)
        let id = UUID()
        // 200x200 / 16 covers 13x13 = 169 cells.
        index.insert(id: id, rect: rect(0, 0, 200, 200))

        XCTAssertEqual(index.ids(intersecting: rect(0, 0, 200, 200)).count, 1)
        XCTAssertEqual(index.ids(intersecting: rect(0, 0, 200, 200)), [id])
        XCTAssertEqual(index.ids(containing: pt(100, 100)), [id])
    }

    func testQueryMatchesBruteForceOnSeededRandomData() {
        var rng = LCG(seed: 0xC0FFEE)
        var index = SpatialIndex(cellSize: 100)
        var entries: [(id: UUID, rect: CanvasRect)] = []

        for _ in 0..<300 {
            let id = UUID()
            let frame = rect(
                rng.double(in: -1_200...1_200),
                rng.double(in: -1_200...1_200),
                rng.double(in: 0...400),
                rng.double(in: 0...400)
            )
            entries.append((id, frame))
            index.insert(id: id, rect: frame)
        }

        XCTAssertEqual(index.count, entries.count)

        for _ in 0..<200 {
            let query = rect(
                rng.double(in: -1_500...1_500),
                rng.double(in: -1_500...1_500),
                rng.double(in: 0...500),
                rng.double(in: 0...500)
            )
            let expected = Set(entries.filter { $0.rect.intersects(query) }.map(\.id))
            XCTAssertEqual(index.ids(intersecting: query), expected, "query \(query)")
        }
    }

    func testContainingPointMatchesBruteForceOnSeededRandomData() {
        var rng = LCG(seed: 0xBEEF)
        var index = SpatialIndex(cellSize: 128)
        var entries: [(id: UUID, rect: CanvasRect)] = []

        for _ in 0..<200 {
            let id = UUID()
            let frame = rect(
                rng.double(in: -800...800),
                rng.double(in: -800...800),
                rng.double(in: 0...250),
                rng.double(in: 0...250)
            )
            entries.append((id, frame))
            index.insert(id: id, rect: frame)
        }

        for _ in 0..<300 {
            let point = pt(rng.double(in: -1_000...1_000), rng.double(in: -1_000...1_000))
            let expected = Set(entries.filter { $0.rect.contains(point) }.map(\.id))
            XCTAssertEqual(index.ids(containing: point), expected, "point \(point)")
        }
    }

    func testExtremelyLargeRectsCurrentlyOnlyRegisterTheirOriginCell() {
        // Known limitation: `SpatialIndex.cellKeys(for:)` (SpatialIndex.swift:129)
        // caps a rect at one cell once it would span >= 4096 cells. Such a rect
        // can only be found by queries touching that origin cell, contradicting
        // the documented promise on `ids(intersecting:)` that an overlapping
        // oversized node is still returned.
        var index = SpatialIndex(cellSize: 512)
        let id = UUID()
        index.insert(id: id, rect: rect(0, 0, 200_000, 200_000))

        XCTAssertEqual(index.ids(containing: pt(1, 1)), [id], "Origin cell still works")

        XCTExpectFailure(
            "Known bug: a rect spanning >= 4096 cells is stored in a single origin cell.",
            strict: false
        ) {
            XCTAssertEqual(index.ids(intersecting: rect(100_000, 100_000, 10, 10)), [id])
        }
    }

    // MARK: Nearest

    func testNearestSortsByDistanceAndHonorsLimit() {
        var index = SpatialIndex(cellSize: 100)
        let near = UUID()
        let middle = UUID()
        let far = UUID()
        let tooFar = UUID()
        index.insert(id: near, rect: rect(0, 0, 10, 10))       // 10 from probe
        index.insert(id: middle, rect: rect(50, 0, 10, 10))    // 30 from probe
        index.insert(id: far, rect: rect(90, 0, 10, 10))       // 70 from probe
        index.insert(id: tooFar, rect: rect(500, 0, 10, 10))   // 480 from probe

        let probe = pt(20, 0)
        XCTAssertEqual(index.nearest(to: probe, limit: 1, maxDistance: 1_000), [near])
        XCTAssertEqual(index.nearest(to: probe, limit: 2, maxDistance: 1_000), [near, middle])
        XCTAssertEqual(index.nearest(to: probe, limit: 10, maxDistance: 1_000), [near, middle, far, tooFar])
        XCTAssertEqual(index.nearest(to: probe, limit: 10, maxDistance: 100), [near, middle, far])
        XCTAssertTrue(index.nearest(to: probe, limit: 10, maxDistance: 5).isEmpty)
    }

    func testNearestIncludesRectContainingPointAtDistanceZero() {
        var index = SpatialIndex(cellSize: 100)
        let id = UUID()
        index.insert(id: id, rect: rect(0, 0, 100, 100))
        XCTAssertEqual(index.nearest(to: pt(50, 50), limit: 1, maxDistance: 100), [id])
    }

    func testNearestWithVeryLargeMaxDistanceMissesRectsAwayFromOrigin() {
        // Known limitation shared with `cellKeys(for:)`: the probe rect for a
        // very large `maxDistance` spans >= 4096 cells, so only one origin cell
        // is scanned. (The default `.infinity` value additionally overflows the
        // `Int` multiplication in the cell-count guard and traps; see the report.)
        var index = SpatialIndex(cellSize: 512)
        let id = UUID()
        index.insert(id: id, rect: rect(0, 0, 10, 10))

        XCTExpectFailure(
            "Known bug: nearest() with a large maxDistance scans a single cell.",
            strict: false
        ) {
            XCTAssertEqual(index.nearest(to: pt(5, 5), limit: 1, maxDistance: 1e9), [id])
        }
    }
}
