import XCTest
@testable import SunroomCore

final class ModelTests: XCTestCase {

    // MARK: Codable

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func sampleDocument() -> CanvasDocument {
        let groupID = UUID()
        let nodes = [
            makeNode(kind: .group, frame: rect(-100, -100, 800, 600), title: "Frame", style: NodeStyle(accent: ColorToken.slate.rawValue, cornerRadius: 24)),
            makeNode(kind: .note, frame: rect(0, 0, 200, 150), title: "Note", text: "Body text", style: NodeStyle(
                    accent: ColorToken.apricot.rawValue,
                    fill: "#FFAA00",
                    textColor: "#111111",
                    fontSize: 17,
                    cornerRadius: 12,
                    opacity: 0.9,
                    imageContentMode: "fill"
                ), groupID: groupID),
            makeNode(kind: .window, frame: rect(250, 20, 400, 300), title: "Window", windowReference: windowReference()),
            makeNode(kind: .link, frame: rect(0, 400, 300, 100), title: "Example", linkURL: "https://example.com/article"),
            makeNode(kind: .image, frame: rect(400, 400, 300, 200), imageAssetName: "asset.png"),
        ]
        return makeDocument(
            name: "Codable Canvas",
            nodes: nodes,
            transform: CanvasTransform(translation: pt(12.5, -7.25), zoom: 1.75),
            background: .midnight,
            gridStyle: .lines,
            gridSpacing: 32,
            notes: "Some notes"
        )
    }

    func testCanvasDocumentCodableRoundTrip() throws {
        let document = sampleDocument()
        let data = try makeEncoder().encode(document)
        let decoded = try makeDecoder().decode(CanvasDocument.self, from: data)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.id, document.id)
        XCTAssertEqual(decoded.name, document.name)
        XCTAssertEqual(decoded.nodes.count, document.nodes.count)
        XCTAssertEqual(decoded.createdAt, document.createdAt)
        XCTAssertEqual(decoded.updatedAt, document.updatedAt)
        XCTAssertEqual(decoded.notes, document.notes)
        XCTAssertEqual(decoded.transform, document.transform)
        XCTAssertEqual(decoded.background, .midnight)
        XCTAssertEqual(decoded.gridStyle, .lines)
        XCTAssertEqual(decoded.gridSpacing, 32)
    }

    func testCanvasNodeCodableRoundTrip() throws {
        let node = sampleDocument().nodes[1]
        let data = try makeEncoder().encode(node)
        let decoded = try makeDecoder().decode(CanvasNode.self, from: data)
        XCTAssertEqual(decoded, node)
        XCTAssertEqual(decoded.style.fill, "#FFAA00")
        XCTAssertEqual(decoded.style.opacity, 0.9)
    }

    func testNodeStyleCodableRoundTripIncludingNils() throws {
        let style = NodeStyle()
        let data = try makeEncoder().encode(style)
        let decoded = try makeDecoder().decode(NodeStyle.self, from: data)
        XCTAssertEqual(decoded, style)
        XCTAssertNil(decoded.fill)
        XCTAssertNil(decoded.textColor)
    }

    func testWindowReferenceCodableRoundTrip() throws {
        let reference = windowReference()
        let data = try makeEncoder().encode(reference)
        let decoded = try makeDecoder().decode(WindowReference.self, from: data)
        XCTAssertEqual(decoded, reference)
    }

    func testDatesAreEncodedAsISO8601Strings() throws {
        let document = sampleDocument()
        let data = try makeEncoder().encode(document)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let createdAt = try XCTUnwrap(object["createdAt"] as? String)
        XCTAssertTrue(createdAt.contains("T"), "ISO8601 timestamps contain a T separator: \(createdAt)")
        XCTAssertTrue(createdAt.hasSuffix("Z"))
    }

    func testUnknownFieldsAreIgnoredWhenDecoding() throws {
        let data = try makeEncoder().encode(sampleDocument())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["aFieldFromTheFuture"] = ["nested": true, "answer": 42]
        object["anotherFutureField"] = "hello"

        let mutated = try JSONSerialization.data(withJSONObject: object)
        let decoded = try makeDecoder().decode(CanvasDocument.self, from: mutated)
        XCTAssertEqual(decoded.name, "Codable Canvas")
    }

    func testDecodingDocumentMissingAFieldCurrentlyThrows() throws {
        // `migrateIfNeeded()` is documented as giving older documents sensible
        // defaults ("Unknown/newer fields are ignored by Codable, older
        // documents get sensible defaults" — DocumentOperations.swift:342), but
        // the synthesized `Decodable` conformance requires every key. A file
        // written before a field existed therefore cannot be decoded at all.
        let data = try makeEncoder().encode(sampleDocument())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "notes")

        let mutated = try JSONSerialization.data(withJSONObject: object)
        try XCTExpectFailure(
            "Known gap: synthesized Codable rejects documents missing a field before migrateIfNeeded() can run.",
            strict: false
        ) {
            XCTAssertNoThrow(try makeDecoder().decode(CanvasDocument.self, from: mutated))
        }
    }

    // MARK: Migration

    func testMigrateIfNeededRepairsInvalidValues() {
        var document = makeDocument(name: "Old", nodes: [makeNode()])
        document.schemaVersion = 0
        document.gridSpacing = 2
        document.transform.zoom = 500 // public var bypasses the init clamp
        document.nodes[0].frame = CanvasRect(origin: pt(10, 10), size: sz(-40, -20))
        document.nodes[0].style.opacity = 0

        document.migrateIfNeeded()

        XCTAssertEqual(document.schemaVersion, CanvasDocument.currentSchemaVersion)
        XCTAssertEqual(document.gridSpacing, 48)
        XCTAssertEqual(document.transform.zoom, 1)
        XCTAssertEqual(document.nodes[0].frame, rect(-30, -10, 40, 20))
        XCTAssertEqual(document.nodes[0].style.opacity, 1)
    }

    func testMigrateIfNeededLeavesValidValuesAlone() {
        var document = makeDocument(
            nodes: [makeNode(frame: rect(1, 2, 3, 4))],
            transform: CanvasTransform(translation: pt(5, 6), zoom: 2.5),
            gridSpacing: 64
        )
        let original = document
        document.migrateIfNeeded()
        XCTAssertEqual(document.schemaVersion, original.schemaVersion)
        XCTAssertEqual(document.gridSpacing, 64)
        XCTAssertEqual(document.transform, original.transform)
        XCTAssertEqual(document.nodes[0].frame, original.nodes[0].frame)
        XCTAssertEqual(document.nodes[0].style.opacity, 1)
    }

    func testDocumentInitClampsGridSpacing() {
        XCTAssertEqual(makeDocument(gridSpacing: 1).gridSpacing, 8)
        XCTAssertEqual(makeDocument(gridSpacing: 8).gridSpacing, 8)
        XCTAssertEqual(makeDocument(gridSpacing: 200).gridSpacing, 200)
    }

    func testNodeInitStandardizesFrame() {
        let node = makeNode(frame: CanvasRect(origin: pt(10, 20), size: sz(-5, -8)))
        XCTAssertEqual(node.frame, rect(5, 12, 5, 8))
    }

    // MARK: Display label

    func testDisplayLabelPrefersTitle() {
        let node = makeNode(title: "  Chosen title  ", text: "Body")
        XCTAssertEqual(node.displayLabel, "  Chosen title  ")
    }

    func testDisplayLabelFallsBackToWindowTitleThenAppName() {
        let titled = makeNode(title: "   ", windowReference: windowReference(windowTitle: "Quarterly Report", appName: "Numbers"))
        XCTAssertEqual(titled.displayLabel, "Quarterly Report")

        let appOnly = makeNode(title: "", windowReference: windowReference(windowTitle: "", appName: "Numbers"))
        XCTAssertEqual(appOnly.displayLabel, "Numbers")
    }

    func testDisplayLabelFallsBackToLinkHost() {
        let node = makeNode(title: "", text: "Ignored body", linkURL: "https://example.com/path?q=1")
        XCTAssertEqual(node.displayLabel, "example.com")
    }

    func testDisplayLabelFallsBackToTextForHostlessLinks() {
        // `displayLabel` only uses the URL host when one exists; otherwise it
        // falls through to the text prefix (`Models.swift:170-176`).
        let hostless = makeNode(title: "", text: "Read me", linkURL: "not a url")
        XCTAssertEqual(hostless.displayLabel, "Read me")

        let unparseable = makeNode(title: "", text: "Read me", linkURL: "")
        XCTAssertEqual(unparseable.displayLabel, "Read me")
    }

    func testDisplayLabelUsesTrimmedTextPrefix() {
        let short = makeNode(text: "  hello world  ")
        XCTAssertEqual(short.displayLabel, "hello world")

        let long = makeNode(text: String(repeating: "x", count: 80))
        XCTAssertEqual(long.displayLabel.count, 60)
        XCTAssertEqual(long.displayLabel, String(repeating: "x", count: 60))
    }

    func testDisplayLabelFallsBackToKindName() {
        XCTAssertEqual(makeNode(kind: .note).displayLabel, "Note")
        XCTAssertEqual(makeNode(kind: .group).displayLabel, "Frame")
        XCTAssertEqual(makeNode(kind: .window).displayLabel, "Window")
    }

    func testSearchableTextCombinesFields() {
        let node = makeNode(title: "Title", text: "Body", linkURL: "https://example.com", windowReference: windowReference(windowTitle: "Window Title", appName: "Editor"))
        let searchable = node.searchableText
        XCTAssertTrue(searchable.contains("Title"))
        XCTAssertTrue(searchable.contains("Body"))
        XCTAssertTrue(searchable.contains("https://example.com"))
        XCTAssertTrue(searchable.contains("Window Title"))
        XCTAssertTrue(searchable.contains("Editor"))
    }

    // MARK: Painting & hit testing

    func testPaintOrderPutsContainersFirstPreservingOrder() {
        let noteA = makeNode(kind: .note, title: "A")
        let group1 = makeNode(kind: .group, title: "G1")
        let noteB = makeNode(kind: .note, title: "B")
        let group2 = makeNode(kind: .group, title: "G2")
        let document = makeDocument(nodes: [noteA, group1, noteB, group2])

        XCTAssertEqual(document.paintOrder.map(\.title), ["G1", "G2", "A", "B"])
    }

    func testPaintOrderStableForAllContainers() {
        let a = makeNode(kind: .group, title: "A")
        let b = makeNode(kind: .note, title: "B")
        let document = makeDocument(nodes: [a, b])
        XCTAssertEqual(document.paintOrder.map(\.title), ["A", "B"])
    }

    func testHitTestUsesTopmostNode() {
        let bottom = makeNode(frame: rect(0, 0, 100, 100), title: "bottom")
        let top = makeNode(frame: rect(50, 50, 100, 100), title: "top")
        let document = makeDocument(nodes: [bottom, top])

        XCTAssertEqual(document.hitTest(pt(75, 75))?.title, "top")
        XCTAssertEqual(document.hitTest(pt(25, 25))?.title, "bottom")
        XCTAssertNil(document.hitTest(pt(300, 300)))
    }

    func testHitTestRespectsLockedNodes() {
        let bottom = makeNode(frame: rect(0, 0, 100, 100), title: "bottom")
        let top = makeNode(frame: rect(0, 0, 100, 100), title: "top", isLocked: true)
        let document = makeDocument(nodes: [bottom, top])

        XCTAssertEqual(document.hitTest(pt(10, 10))?.title, "bottom")
        XCTAssertEqual(document.hitTest(pt(10, 10), includingLocked: true)?.title, "top")
    }

    func testHitTestIncludesEdges() {
        let node = makeNode(frame: rect(0, 0, 100, 100), title: "node")
        let document = makeDocument(nodes: [node])
        XCTAssertEqual(document.hitTest(pt(0, 0))?.title, "node")
        XCTAssertEqual(document.hitTest(pt(100, 100))?.title, "node")
    }

    // MARK: Document queries

    func testNodeLookupAndIndex() {
        let a = makeNode(title: "a")
        let b = makeNode(title: "b")
        let document = makeDocument(nodes: [a, b])
        XCTAssertEqual(document.node(withID: b.id)?.title, "b")
        XCTAssertEqual(document.index(of: b.id), 1)
        XCTAssertNil(document.node(withID: UUID()))
        XCTAssertNil(document.index(of: UUID()))
    }

    func testBoundsAndChildren() {
        let groupID = UUID()
        let childA = makeNode(frame: rect(0, 0, 10, 10), groupID: groupID)
        let childB = makeNode(frame: rect(50, 50, 10, 10), groupID: groupID)
        let unrelated = makeNode(frame: rect(100, 100, 10, 10))
        let group = makeNode(kind: .group, frame: rect(-5, -5, 100, 100), id: groupID)
        let document = makeDocument(nodes: [group, childA, childB, unrelated])

        XCTAssertEqual(document.bounds, rect(-5, -5, 115, 115))
        XCTAssertEqual(document.children(of: groupID).map(\.id), [childA.id, childB.id])
    }

    func testBoundsOfEmptyDocumentIsNil() {
        XCTAssertNil(makeDocument().bounds)
    }

    func testCanvasSummary() {
        let document = makeDocument(name: "Summary", nodes: [makeNode(frame: rect(0, 0, 10, 20))])
        let summary = document.canvasSummary
        XCTAssertEqual(summary.id, document.id)
        XCTAssertEqual(summary.name, "Summary")
        XCTAssertEqual(summary.nodeCount, 1)
        XCTAssertEqual(summary.background, .aurora)
        XCTAssertEqual(summary.previewBounds, rect(0, 0, 10, 20))
        XCTAssertEqual(summary.updatedAt, document.updatedAt)
    }

    func testNodesIntersecting() {
        let a = makeNode(frame: rect(0, 0, 10, 10))
        let b = makeNode(frame: rect(100, 100, 10, 10), isLocked: true)
        let document = makeDocument(nodes: [a, b])

        XCTAssertEqual(document.nodes(intersecting: rect(0, 0, 200, 200)).count, 2)
        XCTAssertEqual(document.nodes(intersecting: rect(0, 0, 200, 200), includingLocked: false).map(\.id), [a.id])
    }

    // MARK: Kind / palette metadata

    func testNodeKindMetadata() {
        XCTAssertTrue(NodeKind.group.isContainer)
        XCTAssertFalse(NodeKind.note.isContainer)
        XCTAssertTrue(NodeKind.note.isTextual)
        XCTAssertTrue(NodeKind.text.isTextual)
        XCTAssertFalse(NodeKind.window.isTextual)
        XCTAssertTrue(NodeKind.window.isSnapshotable)
        XCTAssertTrue(NodeKind.image.isSnapshotable)
        XCTAssertTrue(NodeKind.link.isSnapshotable)
        XCTAssertFalse(NodeKind.shape.isSnapshotable)
        XCTAssertEqual(NodeKind.group.displayName, "Frame")
        XCTAssertFalse(NodeKind.group.symbolName.isEmpty)
    }

    func testBackgroundAndGridMetadata() {
        XCTAssertTrue(CanvasBackground.graphite.isDark)
        XCTAssertTrue(CanvasBackground.midnight.isDark)
        XCTAssertFalse(CanvasBackground.paper.isDark)
        XCTAssertFalse(CanvasBackground.aurora.isDark)
        XCTAssertEqual(GridStyle.none.displayName, "None")
        XCTAssertEqual(ColorToken.allCases.count, 9)
        XCTAssertEqual(ColorToken.sunflower.displayName, "Sunflower")
    }
}
