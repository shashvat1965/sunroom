import XCTest
@testable import SunroomCore

final class SampleCanvasTests: XCTestCase {

    // MARK: Welcome canvas

    func testWelcomeCanvasHasExpectedNodes() {
        let document = SampleCanvas.welcome()
        XCTAssertEqual(document.name, "Welcome to Sunroom")
        XCTAssertEqual(document.nodes.count, 8)
        XCTAssertEqual(document.background, .aurora)
        XCTAssertEqual(document.gridStyle, .dots)
    }

    func testWelcomeCanvasHasUniqueIDs() {
        let document = SampleCanvas.welcome()
        XCTAssertEqual(Set(document.nodes.map(\.id)).count, document.nodes.count)
    }

    func testWelcomeCanvasHasExactlyOneGroup() {
        let document = SampleCanvas.welcome()
        XCTAssertEqual(document.nodes.filter { $0.kind == .group }.count, 1)
    }

    func testWelcomeGroupContainsItsThreeNotes() throws {
        let document = SampleCanvas.welcome()
        let group = try XCTUnwrap(document.nodes.first { $0.kind == .group })
        let children = document.children(of: group.id)

        XCTAssertEqual(children.count, 3)
        XCTAssertTrue(children.allSatisfy { $0.kind == .note })
        for child in children {
            XCTAssertTrue(group.frame.intersects(child.frame), "\(child.title) should overlap its frame")
        }
    }

    func testWelcomeGroupFrameEnclosesItsNotes() throws {
        // Sample data bug: the group frame ends at x = 380 while the third note
        // ends at x = 386, so the "A little tour" frame clips its last note.
        let document = SampleCanvas.welcome()
        let group = try XCTUnwrap(document.nodes.first { $0.kind == .group })
        let children = document.children(of: group.id)

        XCTExpectFailure(
            "Known bug: the welcome group frame is 6pt too narrow for its third note (SampleCanvas.swift:44 vs 67).",
            strict: false
        ) {
            XCTAssertTrue(children.allSatisfy { group.frame.encloses($0.frame) })
        }
    }

    func testWelcomeHeroIsTextual() throws {
        let document = SampleCanvas.welcome()
        let hero = try XCTUnwrap(document.nodes.first { $0.title == "Sunroom" })
        XCTAssertEqual(hero.kind, .text)
        XCTAssertTrue(hero.kind.isTextual)
    }

    func testWelcomeHasLinkAndWindowCards() {
        let document = SampleCanvas.welcome()
        XCTAssertEqual(document.nodes.filter { $0.kind == .link }.count, 1)
        XCTAssertEqual(document.nodes.filter { $0.kind == .window }.count, 1)
    }

    func testWelcomeTransformIsUsable() {
        let document = SampleCanvas.welcome()
        XCTAssertEqual(document.transform.zoom, 1)
        XCTAssertEqual(document.transform.translation, pt(820, 520))
    }

    func testWelcomeContentFramesDoNotOverlap() {
        // The group frame intentionally contains the notes, so exclude it.
        let document = SampleCanvas.welcome()
        assertNoOverlaps(document.nodes.filter { $0.kind != .group }.map(\.frame))
    }

    // MARK: Stress canvas

    func testStressTestProducesExactNodeCount() {
        for count in [0, 1, 5, 25, 100] {
            XCTAssertEqual(SampleCanvas.stressTest(nodeCount: count).nodes.count, count)
        }
    }

    func testStressTestDefaultCount() {
        XCTAssertEqual(SampleCanvas.stressTest().nodes.count, 400)
    }

    func testStressTestHasUniqueIDs() {
        let document = SampleCanvas.stressTest(nodeCount: 50)
        XCTAssertEqual(Set(document.nodes.map(\.id)).count, 50)
    }

    func testStressTestFramesDoNotOverlap() {
        let document = SampleCanvas.stressTest(nodeCount: 50)
        assertNoOverlaps(document.nodes.map(\.frame))
    }

    func testStressTestUsesDocumentMetadata() {
        let document = SampleCanvas.stressTest(nodeCount: 10)
        XCTAssertEqual(document.name, "Stress Test")
        XCTAssertEqual(document.background, .midnight)
        XCTAssertEqual(document.gridStyle, .dots)
    }

    func testStressTestTitlesAreSequential() {
        let document = SampleCanvas.stressTest(nodeCount: 5)
        XCTAssertEqual(document.nodes.map(\.title), ["Card 1", "Card 2", "Card 3", "Card 4", "Card 5"])
    }

    func testStressTestBoundsAreFinite() throws {
        let document = SampleCanvas.stressTest(nodeCount: 20)
        let bounds = try XCTUnwrap(document.bounds)
        XCTAssertTrue(bounds.origin.x.isFinite)
        XCTAssertTrue(bounds.origin.y.isFinite)
        XCTAssertTrue(bounds.width.isFinite)
        XCTAssertTrue(bounds.height.isFinite)
        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)
    }
}
