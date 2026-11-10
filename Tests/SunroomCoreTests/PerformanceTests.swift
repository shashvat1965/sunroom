import XCTest
@testable import SunroomCore

/// Coarse performance smoke tests. The thresholds are deliberately generous:
/// they catch accidental quadratic blowups, not micro-regressions, and they
/// must be stable on a busy CI machine in a debug build.
final class PerformanceTests: XCTestCase {

    // MARK: Spatial index

    private func makeIndex(count: Int, seed: UInt64) -> (SpatialIndex, [(id: UUID, rect: CanvasRect)]) {
        var rng = LCG(seed: seed)
        var index = SpatialIndex(cellSize: 256)
        var entries: [(id: UUID, rect: CanvasRect)] = []
        entries.reserveCapacity(count)

        for _ in 0..<count {
            let id = UUID()
            let frame = rect(
                rng.double(in: -40_000...40_000),
                rng.double(in: -40_000...40_000),
                rng.double(in: 80...400),
                rng.double(in: 60...300)
            )
            entries.append((id, frame))
            index.insert(id: id, rect: frame)
        }
        return (index, entries)
    }

    func testSpatialIndexWithTwentyThousandRectsQueriesQuickly() {
        let (index, entries) = makeIndex(count: 20_000, seed: 0x5EED)
        XCTAssertEqual(index.count, 20_000)

        var rng = LCG(seed: 99)
        let viewportQueries = (0..<100).map { _ in
            rect(
                rng.double(in: -40_000...40_000),
                rng.double(in: -40_000...40_000),
                1_600,
                1_000
            )
        }

        // Correctness at scale: one query matches a brute-force scan.
        let spotCheck = viewportQueries[0]
        let expected = Set(entries.filter { $0.rect.intersects(spotCheck) }.map(\.id))
        XCTAssertEqual(index.ids(intersecting: spotCheck), expected)

        measure {
            for query in viewportQueries {
                _ = index.ids(intersecting: query)
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        for query in viewportQueries {
            _ = index.ids(intersecting: query)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 0.5, "100 viewport queries against 20k rects took \(elapsed)s")
    }

    // MARK: Coordinate mapping

    func testMappingOneHundredThousandPointsIsFast() {
        var rng = LCG(seed: 0xCAFE)
        let points = (0..<100_000).map { _ in
            pt(rng.double(in: -100_000...100_000), rng.double(in: -100_000...100_000))
        }
        let transform = CanvasTransform(translation: pt(120.5, -44.25), zoom: 1.75)
        var checksum = 0.0

        measure {
            checksum = 0
            for point in points {
                let mapped = transform.screenPoint(fromCanvas: point)
                checksum += mapped.x + mapped.y
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        var manualChecksum = 0.0
        for point in points {
            let mapped = transform.screenPoint(fromCanvas: point)
            manualChecksum += mapped.x + mapped.y
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertTrue(manualChecksum.isFinite)
        XCTAssertEqual(checksum, manualChecksum, accuracy: 1e-6)
        XCTAssertLessThan(elapsed, 0.5, "Mapping 100k points took \(elapsed)s")
    }

    func testCanvasToScreenAndBackIsFastAtScale() {
        var rng = LCG(seed: 0xFEED)
        let points = (0..<50_000).map { _ in
            pt(rng.double(in: -10_000...10_000), rng.double(in: -10_000...10_000))
        }
        let transform = CanvasTransform(translation: pt(-9, 7), zoom: 0.6)

        let start = CFAbsoluteTimeGetCurrent()
        for point in points {
            _ = transform.canvasPoint(fromScreen: transform.screenPoint(fromCanvas: point))
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 0.5, "50k bidirectional mappings took \(elapsed)s")
    }
}
