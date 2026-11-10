import XCTest
@testable import SunroomCore

final class DocumentOperationsTests: XCTestCase {

    // MARK: Insertion

    func testInsertAppendsAndReturnsID() {
        var document = makeDocument()
        let node = makeNode(title: "A")
        let returned = document.insert(node)
        XCTAssertEqual(returned, node.id)
        XCTAssertEqual(document.nodes.count, 1)
        XCTAssertEqual(document.nodes[0].id, node.id)
    }

    func testInsertAtValidIndex() {
        var document = makeDocument(nodes: [makeNode(title: "A")])
        let b = makeNode(title: "B")
        document.insert(b, at: 0)
        XCTAssertEqual(document.nodes.map(\.title), ["B", "A"])
    }

    func testInsertAtOutOfRangeIndexAppends() {
        var document = makeDocument(nodes: [makeNode(title: "A")])
        document.insert(makeNode(title: "B"), at: 99)
        document.insert(makeNode(title: "C"), at: -1)
        XCTAssertEqual(document.nodes.map(\.title), ["A", "B", "C"])
    }

    func testInsertOnTopMovesNodeToFront() {
        // `insertOnTop` is documented as inserting "in front of everything
        // except containers", and `hitTest` treats later array positions as
        // topmost. It currently inserts directly after the containers, i.e. at
        // the *back* of the non-container stack.
        var document = makeDocument(nodes: [makeNode(title: "A"), makeNode(title: "B")])
        let top = makeNode(title: "Top")
        document.insertOnTop(top)

        XCTAssertEqual(document.nodes.count, 3)
        XCTAssertEqual(ids(of: document), Set(document.nodes.map(\.id)))
        XCTExpectFailure(
            "Known bug: insertOnTop inserts at the bottom of the non-container stack (DocumentOperations.swift:28-31).",
            strict: false
        ) {
            XCTAssertEqual(document.nodes.last?.id, top.id)
        }
    }

    func testInsertOnTopKeepsContainersBehind() {
        let group = makeNode(kind: .group, frame: rect(0, 0, 500, 500))
        var document = makeDocument(nodes: [group, makeNode(title: "A")])
        let top = makeNode(title: "Top")
        document.insertOnTop(top)

        XCTAssertEqual(document.nodes.first?.id, group.id)
        XCTAssertEqual(document.nodes.count, 3)
    }

    // MARK: Removal

    func testRemoveReturnsRemovedNodes() {
        var document = makeDocument(nodes: [makeNode(title: "A"), makeNode(title: "B")])
        let removed = document.remove(ids: [document.nodes[0].id])
        XCTAssertEqual(removed.map(\.title), ["A"])
        XCTAssertEqual(document.nodes.map(\.title), ["B"])
    }

    func testRemoveEmptySetIsNoOp() {
        var document = makeDocument(nodes: [makeNode(title: "A")])
        XCTAssertTrue(document.remove(ids: []).isEmpty)
        XCTAssertEqual(document.nodes.count, 1)
    }

    func testRemoveReparentsOrphansOutOfDeletedGroups() {
        let group = makeNode(kind: .group, title: "G")
        let child = makeNode(title: "Child", groupID: group.id)
        var document = makeDocument(nodes: [group, child])

        let removed = document.remove(ids: [group.id])

        XCTAssertEqual(removed.map(\.id), [group.id])
        XCTAssertNil(document.nodes[0].groupID, "The child is re-parented to the root")
    }

    func testRemoveSingleIDReturnsNode() {
        var document = makeDocument(nodes: [makeNode(title: "A")])
        let removed = document.remove(id: document.nodes[0].id)
        XCTAssertEqual(removed?.title, "A")
        XCTAssertTrue(document.nodes.isEmpty)
        XCTAssertNil(document.remove(id: UUID()))
    }

    // MARK: Movement

    func testMoveOffsetsUnlockedNodes() {
        let a = makeNode(frame: rect(0, 0, 10, 10))
        let b = makeNode(frame: rect(100, 100, 10, 10))
        var document = makeDocument(nodes: [a, b])

        document.move(ids: [a.id], by: pt(5, -7))

        XCTAssertEqual(document.nodes[0].frame, rect(5, -7, 10, 10))
        XCTAssertEqual(document.nodes[1].frame, b.frame)
    }

    func testMoveSkipsLockedNodes() {
        let locked = makeNode(frame: rect(0, 0, 10, 10), isLocked: true)
        let unlocked = makeNode(frame: rect(20, 0, 10, 10))
        var document = makeDocument(nodes: [locked, unlocked])

        document.move(ids: [locked.id, unlocked.id], by: pt(10, 10))

        XCTAssertEqual(document.nodes[0].frame, locked.frame)
        XCTAssertEqual(document.nodes[1].frame, rect(30, 10, 10, 10))
    }

    func testMoveByZeroIsNoOp() {
        let a = makeNode(frame: rect(1, 2, 3, 4))
        var document = makeDocument(nodes: [a])
        document.move(ids: [a.id], by: .zero)
        XCTAssertEqual(document.nodes[0].frame, a.frame)
    }

    func testNudge() {
        let a = makeNode(frame: rect(0, 0, 10, 10))
        var document = makeDocument(nodes: [a])
        document.nudge(ids: [a.id], dx: 1, dy: -2)
        XCTAssertEqual(document.nodes[0].frame, rect(1, -2, 10, 10))
    }

    // MARK: Resizing & frames

    func testResizeEnforcesMinimumSize() {
        let node = makeNode(frame: rect(0, 0, 10, 10))
        var document = makeDocument(nodes: [node])

        document.resize(id: node.id, to: rect(5, 5, 10, 10))

        XCTAssertEqual(document.nodes[0].frame, rect(5, 5, 60, 44))
    }

    func testResizeHonorsCustomMinimum() {
        let node = makeNode(frame: rect(0, 0, 100, 100))
        var document = makeDocument(nodes: [node])
        document.resize(id: node.id, to: rect(0, 0, 10, 20), minimum: sz(30, 40))
        XCTAssertEqual(document.nodes[0].frame, rect(0, 0, 30, 40))
    }

    func testResizeStandardizesNegativeFrame() {
        let node = makeNode(frame: rect(0, 0, 100, 100))
        var document = makeDocument(nodes: [node])
        document.resize(id: node.id, to: CanvasRect(origin: pt(100, 100), size: sz(-50, -50)))
        XCTAssertEqual(document.nodes[0].frame, rect(50, 50, 60, 50))
    }

    func testResizeSkipsLockedNode() {
        let node = makeNode(frame: rect(0, 0, 100, 100), isLocked: true)
        var document = makeDocument(nodes: [node])
        document.resize(id: node.id, to: rect(0, 0, 10, 10))
        XCTAssertEqual(document.nodes[0].frame, rect(0, 0, 100, 100))
    }

    func testSetFrameStandardizes() {
        let node = makeNode(frame: rect(0, 0, 100, 100))
        var document = makeDocument(nodes: [node])
        document.setFrame(id: node.id, to: CanvasRect(origin: pt(10, 10), size: sz(-20, -30)))
        XCTAssertEqual(document.nodes[0].frame, rect(-10, -20, 20, 30))
    }

    // MARK: Z-order

    func testSendToBack() {
        let a = makeNode(title: "A")
        let b = makeNode(title: "B")
        let c = makeNode(title: "C")
        var document = makeDocument(nodes: [a, b, c])

        document.sendToBack(ids: [b.id])
        XCTAssertEqual(document.nodes.map(\.title), ["B", "A", "C"])
    }

    func testBringForwardMovesOneStepTowardTop() {
        let a = makeNode(title: "A")
        let b = makeNode(title: "B")
        let c = makeNode(title: "C")
        let d = makeNode(title: "D")
        var document = makeDocument(nodes: [a, b, c, d])

        document.bringForward(ids: [b.id])
        XCTAssertEqual(document.nodes.map(\.title), ["A", "C", "B", "D"])
    }

    func testSendBackwardMovesOneStepTowardBottom() {
        let a = makeNode(title: "A")
        let b = makeNode(title: "B")
        let c = makeNode(title: "C")
        let d = makeNode(title: "D")
        var document = makeDocument(nodes: [a, b, c, d])

        document.sendBackward(ids: [c.id])
        XCTAssertEqual(document.nodes.map(\.title), ["A", "C", "B", "D"])
    }

    func testBringForwardKeepsMultiSelectionTogether() {
        let a = makeNode(title: "A")
        let b = makeNode(title: "B")
        let c = makeNode(title: "C")
        let d = makeNode(title: "D")
        var document = makeDocument(nodes: [a, b, c, d])

        document.bringForward(ids: [a.id, b.id])
        XCTAssertEqual(document.nodes.map(\.title), ["C", "A", "B", "D"])
    }

    func testSendBackwardKeepsMultiSelectionTogether() {
        let a = makeNode(title: "A")
        let b = makeNode(title: "B")
        let c = makeNode(title: "C")
        let d = makeNode(title: "D")
        var document = makeDocument(nodes: [a, b, c, d])

        document.sendBackward(ids: [c.id, d.id])
        XCTAssertEqual(document.nodes.map(\.title), ["A", "C", "D", "B"])
    }

    func testBringToFrontMovesNodeToTop() {
        // Later array positions are topmost (see `CanvasDocument.hitTest`).
        let a = makeNode(title: "A")
        let b = makeNode(title: "B")
        let c = makeNode(title: "C")
        let d = makeNode(title: "D")
        var document = makeDocument(nodes: [a, b, c, d])

        document.bringToFront(ids: [c.id])

        XCTAssertEqual(document.nodes.count, 4)
        XCTExpectFailure(
            "Known bug: bringToFront inserts at containerCount, i.e. behind every other non-container node (DocumentOperations.swift:87-94).",
            strict: false
        ) {
            XCTAssertEqual(document.nodes.last?.id, c.id)
        }
    }

    func testBringToFrontPreservesRelativeSelectionOrder() {
        let a = makeNode(title: "A")
        let b = makeNode(title: "B")
        let c = makeNode(title: "C")
        var document = makeDocument(nodes: [a, b, c])

        document.bringToFront(ids: Set([a.id, c.id]))

        let order = document.nodes.map(\.title)
        XCTAssertEqual(order.count, 3)
        XCTAssertEqual(order.filter { $0 == "A" || $0 == "C" }, ["A", "C"])
        XCTAssertEqual(order.firstIndex(of: "A")! < order.firstIndex(of: "C")!, true)
    }

    func testZOrderOperationsAcceptEmptySelection() {
        let document = makeDocument(nodes: [makeNode()])
        var copy = document
        copy.bringToFront(ids: [])
        copy.sendToBack(ids: [])
        copy.bringForward(ids: [])
        copy.sendBackward(ids: [])
        XCTAssertEqual(copy.nodes.map(\.id), document.nodes.map(\.id))
    }

    // MARK: Alignment

    private func alignmentDocument() -> CanvasDocument {
        makeDocument(nodes: [
            makeNode(frame: rect(0, 0, 100, 50), title: "A"),
            makeNode(frame: rect(200, 100, 60, 80), title: "B"),
            makeNode(frame: rect(50, 300, 40, 40), title: "C"),
        ])
    }

    func testAlignLeft() {
        var document = alignmentDocument()
        document.align(ids: ids(of: document), to: .left)
        XCTAssertEqual(document.nodes.map { $0.frame.minX }, [0, 0, 0])
    }

    func testAlignRight() {
        var document = alignmentDocument()
        document.align(ids: ids(of: document), to: .right)
        XCTAssertEqual(document.nodes.map { $0.frame.maxX }, [260, 260, 260])
    }

    func testAlignCenterHorizontal() {
        var document = alignmentDocument()
        document.align(ids: ids(of: document), to: .centerHorizontal)
        XCTAssertEqual(document.nodes.map { $0.frame.center.x }, [130, 130, 130])
    }

    func testAlignTop() {
        var document = alignmentDocument()
        document.align(ids: ids(of: document), to: .top)
        XCTAssertEqual(document.nodes.map { $0.frame.minY }, [0, 0, 0])
    }

    func testAlignBottom() {
        var document = alignmentDocument()
        document.align(ids: ids(of: document), to: .bottom)
        XCTAssertEqual(document.nodes.map { $0.frame.maxY }, [340, 340, 340])
    }

    func testAlignCenterVertical() {
        var document = alignmentDocument()
        document.align(ids: ids(of: document), to: .centerVertical)
        XCTAssertEqual(document.nodes.map { $0.frame.center.y }, [170, 170, 170])
    }

    func testAlignUsesExplicitReference() {
        var document = alignmentDocument()
        // A reference far outside the selection must move nodes, never stretch them.
        document.align(ids: ids(of: document), to: .left, relativeTo: rect(500, 500, 50, 50))
        XCTAssertEqual(document.nodes.map { $0.frame.minX }, [500, 500, 500])
        XCTAssertEqual(document.nodes.map(\.frame.size), [sz(100, 50), sz(60, 80), sz(40, 40)])
    }

    func testAlignIgnoresLockedNodes() {
        var document = makeDocument(nodes: [
            makeNode(frame: rect(0, 0, 100, 50), title: "A"),
            makeNode(frame: rect(300, 0, 100, 50), title: "Locked", isLocked: true),
        ])
        document.align(ids: ids(of: document), to: .left)
        XCTAssertEqual(document.nodes[0].frame.minX, 0)
        XCTAssertEqual(document.nodes[1].frame.minX, 300)
    }

    // MARK: Distribution

    func testDistributeHorizontallyEqualizesGaps() {
        var document = makeDocument(nodes: [
            makeNode(frame: rect(0, 0, 100, 50), title: "A"),
            makeNode(frame: rect(150, 0, 50, 50), title: "B"),
            makeNode(frame: rect(400, 0, 80, 50), title: "C"),
        ])
        document.distribute(ids: ids(of: document), horizontally: true)

        XCTAssertEqual(document.nodes.map { $0.frame.minX }, [0, 225, 400])
        XCTAssertEqual(document.nodes[1].frame.minX - document.nodes[0].frame.maxX, 125)
        XCTAssertEqual(document.nodes[2].frame.minX - document.nodes[1].frame.maxX, 125)
        XCTAssertEqual(document.bounds, rect(0, 0, 480, 50))
    }

    func testDistributeVerticallyEqualizesGaps() {
        var document = makeDocument(nodes: [
            makeNode(frame: rect(0, 0, 100, 100), title: "A"),
            makeNode(frame: rect(0, 150, 100, 50), title: "B"),
            makeNode(frame: rect(0, 400, 100, 80), title: "C"),
        ])
        document.distribute(ids: ids(of: document), horizontally: false)

        XCTAssertEqual(document.nodes.map { $0.frame.minY }, [0, 225, 400])
        XCTAssertEqual(document.nodes[1].frame.minY - document.nodes[0].frame.maxY, 125)
        XCTAssertEqual(document.nodes[2].frame.minY - document.nodes[1].frame.maxY, 125)
    }

    func testDistributeHonorsExplicitGap() {
        var document = makeDocument(nodes: [
            makeNode(frame: rect(0, 0, 100, 50), title: "A"),
            makeNode(frame: rect(200, 0, 50, 50), title: "B"),
        ])
        document.distribute(ids: ids(of: document), horizontally: true, gap: 10)
        XCTAssertEqual(document.nodes.map { $0.frame.minX }, [0, 110])
    }

    func testDistributeRequiresTwoNodesAndSkipsLocked() {
        var document = makeDocument(nodes: [
            makeNode(frame: rect(0, 0, 10, 10), title: "A"),
            makeNode(frame: rect(100, 0, 10, 10), title: "Locked", isLocked: true),
        ])
        document.distribute(ids: ids(of: document), horizontally: true)
        XCTAssertEqual(document.nodes[0].frame.minX, 0)
        XCTAssertEqual(document.nodes[1].frame.minX, 100)
    }

    // MARK: Grouping

    func testGroupCreatesFrameAndParentsChildren() {
        let a = makeNode(frame: rect(0, 0, 100, 50), title: "A")
        let b = makeNode(frame: rect(200, 0, 50, 50), title: "B")
        var document = makeDocument(nodes: [a, b])

        let groupID = document.group(ids: [a.id, b.id], title: "My Frame")

        let unwrapped = try! XCTUnwrap(groupID)
        let group = try! XCTUnwrap(document.node(withID: unwrapped))
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.title, "My Frame")
        XCTAssertEqual(group.frame, rect(-32, -32, 314, 114))
        XCTAssertEqual(document.nodes.first?.id, unwrapped)
        XCTAssertEqual(document.children(of: unwrapped).map(\.id), [a.id, b.id])
        XCTAssertEqual(document.node(withID: a.id)?.groupID, unwrapped)
    }

    func testGroupRequiresSelection() {
        var document = makeDocument()
        XCTAssertNil(document.group(ids: []))
        XCTAssertNil(document.group(ids: [UUID()]))
    }

    func testUngroupRemovesFrameAndClearsChildren() {
        let group = makeNode(kind: .group, frame: rect(0, 0, 200, 200), title: "G")
        let child = makeNode(frame: rect(10, 10, 50, 50), title: "Child", groupID: group.id)
        var document = makeDocument(nodes: [group, child])

        document.ungroup(ids: [group.id])

        XCTAssertTrue(document.nodes.isEmpty == false)
        XCTAssertNil(document.node(withID: group.id))
        XCTAssertNil(document.nodes[0].groupID)
        XCTAssertEqual(document.nodes[0].id, child.id)
    }

    func testUngroupOnlyAffectsGroups() {
        let note = makeNode(title: "A")
        let group = makeNode(kind: .group, title: "G")
        var document = makeDocument(nodes: [group, note])
        document.ungroup(ids: [note.id])
        XCTAssertEqual(document.nodes.count, 2)
    }

    func testAdoptContainedNodes() {
        let group = makeNode(kind: .group, frame: rect(0, 0, 200, 200), title: "G")
        let inside = makeNode(frame: rect(10, 10, 50, 50), title: "Inside")
        let onBoundary = makeNode(frame: rect(0, 0, 50, 50), title: "Boundary")
        let outside = makeNode(frame: rect(250, 250, 10, 10), title: "Outside")
        let otherGroup = UUID()
        let alreadyGrouped = makeNode(frame: rect(20, 20, 10, 10), title: "Other", groupID: otherGroup)
        var document = makeDocument(nodes: [group, inside, onBoundary, outside, alreadyGrouped])

        document.adoptContainedNodes(inFrame: group.id)

        XCTAssertEqual(makeDocument(nodes: document.nodes).node(withID: inside.id)?.groupID, group.id)
        XCTAssertEqual(document.node(withID: onBoundary.id)?.groupID, group.id)
        XCTAssertNil(document.node(withID: outside.id)?.groupID)
        XCTAssertEqual(document.node(withID: alreadyGrouped.id)?.groupID, otherGroup)
    }

    func testAdoptContainedNodesRequiresGroup() {
        let note = makeNode(kind: .note, frame: rect(0, 0, 100, 100), title: "A")
        let inside = makeNode(frame: rect(10, 10, 10, 10), title: "Inside")
        var document = makeDocument(nodes: [note, inside])
        document.adoptContainedNodes(inFrame: note.id)
        XCTAssertNil(document.nodes[1].groupID)
    }

    // MARK: Duplication

    func testDuplicateOffsetsAndCreatesFreshIDs() {
        let original = makeNode(frame: rect(0, 0, 50, 50), title: "Original")
        var document = makeDocument(nodes: [original])

        let newIDs = document.duplicate(ids: [original.id])

        XCTAssertEqual(newIDs.count, 1)
        XCTAssertEqual(document.nodes.count, 2)
        let copy = try! XCTUnwrap(document.nodes.first { newIDs.contains($0.id) })
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.frame, rect(28, 28, 50, 50))
        XCTAssertEqual(copy.title, "Original Copy")
        XCTAssertEqual(document.nodes[0], original)
    }

    func testDuplicateRemapsGroupIDsWithinSelection() {
        let group = makeNode(kind: .group, frame: rect(0, 0, 300, 300), title: "Group")
        let child = makeNode(frame: rect(10, 10, 50, 50), title: "Child", groupID: group.id)
        var document = makeDocument(nodes: [group, child])

        let newIDs = document.duplicate(ids: [group.id, child.id])

        XCTAssertEqual(newIDs.count, 2)
        let copiedGroup = try! XCTUnwrap(document.nodes.first { newIDs.contains($0.id) && $0.kind == .group })
        let copiedChild = try! XCTUnwrap(document.nodes.first { newIDs.contains($0.id) && $0.kind == .note })
        XCTAssertEqual(copiedChild.groupID, copiedGroup.id)
        XCTAssertNotEqual(copiedGroup.id, group.id)
    }

    func testDuplicateChildWithoutItsGroupKeepsOriginalGroupID() {
        let group = makeNode(kind: .group, title: "Group")
        let child = makeNode(title: "Child", groupID: group.id)
        var document = makeDocument(nodes: [group, child])

        let newIDs = document.duplicate(ids: [child.id])

        let copy = try! XCTUnwrap(document.nodes.first { newIDs.contains($0.id) })
        XCTAssertEqual(copy.groupID, group.id)
    }

    func testDuplicateUnlocksCopy() {
        let locked = makeNode(title: "Locked", isLocked: true)
        var document = makeDocument(nodes: [locked])
        let newIDs = document.duplicate(ids: [locked.id])
        let copy = try! XCTUnwrap(document.nodes.first { newIDs.contains($0.id) })
        XCTAssertFalse(copy.isLocked)
    }

    func testDuplicateEmptySelection() {
        var document = makeDocument(nodes: [makeNode()])
        XCTAssertTrue(document.duplicate(ids: []).isEmpty)
        XCTAssertEqual(document.nodes.count, 1)
    }

    // MARK: Properties

    func testRenameSetTextAndStyle() {
        let node = makeNode()
        var document = makeDocument(nodes: [node])

        document.rename(id: node.id, title: "New title")
        document.setText(id: node.id, text: "New text")
        var style = NodeStyle()
        style.accent = ColorToken.mint.rawValue
        document.setStyle(id: node.id, style: style)

        XCTAssertEqual(document.nodes[0].title, "New title")
        XCTAssertEqual(document.nodes[0].text, "New text")
        XCTAssertEqual(document.nodes[0].style.accent, ColorToken.mint.rawValue)
    }

    func testSetAccentUpdatesSelectionIncludingLocked() {
        var document = makeDocument(nodes: [
            makeNode(title: "A"),
            makeNode(title: "Locked", isLocked: true),
            makeNode(title: "Other"),
        ])
        document.setAccent(ids: [document.nodes[0].id, document.nodes[1].id], accent: .rose)

        XCTAssertEqual(document.nodes[0].style.accent, ColorToken.rose.rawValue)
        XCTAssertEqual(document.nodes[1].style.accent, ColorToken.rose.rawValue)
        XCTAssertEqual(document.nodes[2].style.accent, NodeStyle.default.accent)
    }

    func testToggleLockLocksThenUnlocksSelection() {
        let a = makeNode(title: "A")
        let b = makeNode(title: "B", isLocked: true)
        var document = makeDocument(nodes: [a, b])
        let selection: Set<UUID> = [a.id, b.id]

        document.toggleLock(ids: selection)
        XCTAssertTrue(document.nodes.allSatisfy(\.isLocked))

        document.toggleLock(ids: selection)
        XCTAssertTrue(document.nodes.allSatisfy { !$0.isLocked })
    }

    func testToggleCollapse() {
        let node = makeNode()
        var document = makeDocument(nodes: [node])
        document.toggleCollapse(id: node.id)
        XCTAssertTrue(document.nodes[0].isCollapsed)
        document.toggleCollapse(id: node.id)
        XCTAssertFalse(document.nodes[0].isCollapsed)
    }

    func testBoundsOfSelection() {
        let a = makeNode(frame: rect(0, 0, 50, 50))
        let b = makeNode(frame: rect(100, 100, 50, 50))
        let document = makeDocument(nodes: [a, b])
        XCTAssertEqual(document.bounds(of: [a.id, b.id]), rect(0, 0, 150, 150))
        XCTAssertNil(document.bounds(of: []))
    }

    func testFullyInsideAndTouchingMarquee() {
        let a = makeNode(frame: rect(0, 0, 50, 50))
        let b = makeNode(frame: rect(100, 100, 50, 50))
        let document = makeDocument(nodes: [a, b])

        XCTAssertEqual(document.ids(fullyInside: rect(0, 0, 200, 200)), [a.id, b.id])
        XCTAssertEqual(document.ids(fullyInside: rect(0, 0, 50, 50)), [a.id])
        XCTAssertEqual(document.ids(touching: rect(50, 50, 10, 10)), [a.id])
        XCTAssertEqual(document.ids(touching: rect(60, 60, 10, 10)), [])
    }

    func testTouchUpdatesTimestamp() {
        var document = makeDocument(nodes: [makeNode()])
        let old = document.updatedAt
        document.touch()
        XCTAssertGreaterThan(document.updatedAt, old)
    }
}
