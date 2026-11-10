import Foundation
import XCTest
@testable import SunroomCore

// MARK: - Deterministic randomness

/// A tiny seeded linear-congruential generator.
///
/// Tests must never depend on `SystemRandomNumberGenerator`: a failing
/// randomized test has to reproduce from its seed alone. The low bits of an LCG
/// are notoriously poor, so the generator runs its state through a mixer before
/// returning a value (the "output" half of a PCG).
struct LCG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64 = 0x5EED_CAFE_F00D_1234) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = 6_364_136_223_846_793_005 &* state &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 33)) &* 0xFF51_AFD7_ED55_8CCD
        z = (z ^ (z >> 33)) &* 0xC4CE_B9FE_1A85_EC53
        return z ^ (z >> 33)
    }

    /// Uniform double in `range`. 2^53 is the largest exactly representable
    /// integer in a `Double`.
    mutating func double(in range: ClosedRange<Double> = 0...1) -> Double {
        let unit = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        precondition(range.lowerBound <= range.upperBound)
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    mutating func bool() -> Bool { next() & 1 == 0 }
}

// MARK: - Factory helpers

/// A fixed date with whole seconds so `.iso8601` encoding round-trips exactly.
let testDate = Date(timeIntervalSince1970: 1_700_000_000)
let otherTestDate = Date(timeIntervalSince1970: 1_700_003_600)

func pt(_ x: Double, _ y: Double) -> CanvasPoint { CanvasPoint(x: x, y: y) }

func sz(_ width: Double, _ height: Double) -> CanvasSize {
    CanvasSize(width: width, height: height)
}

func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CanvasRect {
    CanvasRect(x: x, y: y, width: width, height: height)
}

func makeNode(
    kind: NodeKind = .note,
    frame: CanvasRect = CanvasRect(x: 0, y: 0, width: 100, height: 100),
    title: String = "",
    text: String = "",
    style: NodeStyle = .default,
    linkURL: String? = nil,
    imageAssetName: String? = nil,
    windowReference: WindowReference? = nil,
    groupID: UUID? = nil,
    isLocked: Bool = false,
    isCollapsed: Bool = false,
    id: UUID = UUID(),
    createdAt: Date = testDate,
    updatedAt: Date = testDate
) -> CanvasNode {
    CanvasNode(
        id: id,
        kind: kind,
        frame: frame,
        title: title,
        text: text,
        style: style,
        linkURL: linkURL,
        imageAssetName: imageAssetName,
        windowReference: windowReference,
        groupID: groupID,
        isLocked: isLocked,
        isCollapsed: isCollapsed,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
}

func makeDocument(
    name: String = "Test Canvas",
    nodes: [CanvasNode] = [],
    transform: CanvasTransform = .identity,
    background: CanvasBackground = .aurora,
    gridStyle: GridStyle = .dots,
    gridSpacing: Double = 48,
    notes: String = ""
) -> CanvasDocument {
    CanvasDocument(
        name: name,
        nodes: nodes,
        transform: transform,
        background: background,
        gridStyle: gridStyle,
        gridSpacing: gridSpacing,
        createdAt: testDate,
        updatedAt: testDate,
        notes: notes
    )
}

func ids(of document: CanvasDocument) -> Set<UUID> { Set(document.nodes.map(\.id)) }

func windowReference(windowTitle: String = "Document — Editor", appName: String = "Editor") -> WindowReference {
    WindowReference(
        windowNumber: 42,
        ownerPID: 1234,
        bundleIdentifier: "com.example.editor",
        appName: appName,
        windowTitle: windowTitle
    )
}

// MARK: - Assertions

func assertPoint(
    _ actual: CanvasPoint,
    _ expected: CanvasPoint,
    accuracy: Double = 1e-9,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "\(message) (x)", file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "\(message) (y)", file: file, line: line)
}

func assertSize(
    _ actual: CanvasSize,
    _ expected: CanvasSize,
    accuracy: Double = 1e-9,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, "\(message) (width)", file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, "\(message) (height)", file: file, line: line)
}

func assertRect(
    _ actual: CanvasRect,
    _ expected: CanvasRect,
    accuracy: Double = 1e-9,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertPoint(actual.origin, expected.origin, accuracy: accuracy, "\(message) origin", file: file, line: line)
    assertSize(actual.size, expected.size, accuracy: accuracy, "\(message) size", file: file, line: line)
}

/// Asserts that no two rects in `rects` overlap by more than a shared edge.
func assertNoOverlaps(
    _ rects: [CanvasRect],
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for i in rects.indices {
        for j in rects.indices where j > i {
            let intersection = rects[i].intersection(rects[j])
            let overlaps = intersection.map { $0.width > 0 && $0.height > 0 } ?? false
            XCTAssertFalse(
                overlaps,
                "\(message) rects \(i) \(rects[i]) and \(j) \(rects[j]) overlap",
                file: file,
                line: line
            )
        }
    }
}

/// Sort helper so set-based API results can be compared in a stable way.
func sortedIDs(_ ids: Set<UUID>) -> [UUID] { ids.sorted() }
