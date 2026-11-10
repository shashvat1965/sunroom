import XCTest
@testable import SunroomCore

final class SearchTests: XCTestCase {

    // MARK: FuzzyMatcher scoring

    func testPrefixScoresHigherThanSubstring() throws {
        let prefix = try XCTUnwrap(FuzzyMatcher.score(query: "sun", candidate: "Sunroom"))
        let substring = try XCTUnwrap(FuzzyMatcher.score(query: "sun", candidate: "RisingSun"))

        XCTAssertGreaterThan(prefix.score, substring.score)
        XCTAssertEqual(prefix.score, 124)
        XCTAssertEqual(substring.score, 104)
    }

    func testWordStartScoresHigherThanMidWordSubstring() throws {
        let wordStart = try XCTUnwrap(FuzzyMatcher.score(query: "room", candidate: "Sun room"))
        let midWord = try XCTUnwrap(FuzzyMatcher.score(query: "room", candidate: "Sunroom"))

        XCTAssertGreaterThan(wordStart.score, midWord.score)
    }

    func testSeparatorsEarnTheWordStartBonusInBothPaths() {
        // The substring fast path and the scattered path agree: a match that
        // starts after a separator is a word start (100 + 18 - offset 2).
        for candidate in ["a room", "a-room", "a_room", "a/room", "a.room"] {
            let match = try! XCTUnwrap(FuzzyMatcher.score(query: "room", candidate: candidate), candidate)
            XCTAssertEqual(match.score, 116, candidate)
        }

        // A match inside a word does not.
        let midWord = try! XCTUnwrap(FuzzyMatcher.score(query: "oom", candidate: "aroom"))
        XCTAssertEqual(midWord.score, 108)
    }

    func testCamelCaseBoundaryIsRewarded() throws {
        // The scoring documentation (Search.swift:5) promises a bonus for a
        // camel-case boundary. `score(query:candidate:)` lowercases the whole
        // candidate before scanning (Search.swift:18), so `char.isUppercase`
        // can never be true and the +6 branch is unreachable.
        let camel = try XCTUnwrap(FuzzyMatcher.score(query: "sc", candidate: "SunroomCanvas"))
        let flat = try XCTUnwrap(FuzzyMatcher.score(query: "sc", candidate: "Sunroomcx"))

        XCTAssertGreaterThan(camel.score, flat.score)
    }

    func testNonMatchingQueryReturnsNil() {
        XCTAssertNil(FuzzyMatcher.score(query: "zzz", candidate: "abc"))
        XCTAssertNil(FuzzyMatcher.score(query: "abcdef", candidate: "abc"))
        XCTAssertNil(FuzzyMatcher.score(query: "xyz", candidate: ""))
    }

    func testEmptyQueryMatchesEverythingWithZeroScore() throws {
        let match = try XCTUnwrap(FuzzyMatcher.score(query: "   ", candidate: "anything"))
        XCTAssertEqual(match.score, 0)
        XCTAssertTrue(match.matchedRanges.isEmpty)
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "SUN", candidate: "sunroom"))
        XCTAssertNotNil(FuzzyMatcher.score(query: "sun", candidate: "SUNROOM"))
    }

    func testMatchedRangesForPrefix() throws {
        let match = try XCTUnwrap(FuzzyMatcher.score(query: "sun", candidate: "Sunroom"))
        XCTAssertEqual(match.matchedRanges.count, 1)
        XCTAssertEqual(match.matchedRanges[0], 0..<3)
    }

    func testNonContiguousMatchStillSucceeds() {
        let match = FuzzyMatcher.score(query: "srm", candidate: "Sunroom")
        XCTAssertNotNil(match)
    }

    // MARK: Rank

    func testRankPutsBestMatchFirst() {
        let items = ["RisingSun", "Sunroom", "Sunset"]
        let ranked = FuzzyMatcher.rank(items, query: "sun") { $0 }
        XCTAssertEqual(ranked.first, "Sunroom")
    }

    func testRankFiltersNonMatches() {
        let items = ["Sunroom", "Moon", "Sunset"]
        let ranked = FuzzyMatcher.rank(items, query: "sun") { $0 }
        XCTAssertEqual(Set(ranked), ["Sunroom", "Sunset"])
        XCTAssertFalse(ranked.contains("Moon"))
    }

    func testRankTieBreaksByKeyDeterministically() {
        let items = ["ycat", "xcat"]
        let forward = FuzzyMatcher.rank(items, query: "cat") { $0 }
        let reversed = FuzzyMatcher.rank(items.reversed(), query: "cat") { $0 }
        XCTAssertEqual(forward, ["xcat", "ycat"])
        XCTAssertEqual(reversed, forward)
    }

    func testRankWithEmptyQueryReturnsInputOrder() {
        let items = ["b", "a", "c"]
        XCTAssertEqual(FuzzyMatcher.rank(items, query: "  ") { $0 }, items)
    }

    func testRankUsesKeyClosure() {
        struct Item { let name: String; let id: Int }
        let items = [Item(name: "Moon", id: 1), Item(name: "Sunroom", id: 2)]
        let ranked = FuzzyMatcher.rank(items, query: "sun") { $0.name }
        XCTAssertEqual(ranked.map(\.id), [2])
    }

    // MARK: Document search

    func testDocumentSearchRanksTitleMatchAboveBodyMatch() {
        let titleMatch = makeNode(title: "Review", text: "")
        let bodyMatch = makeNode(title: "Other", text: "Review this later")
        let document = makeDocument(nodes: [bodyMatch, titleMatch])

        let hits = document.search("review")

        XCTAssertEqual(hits.map(\.id), [titleMatch.id, bodyMatch.id])
        XCTAssertGreaterThan(hits[0].score, hits[1].score)
    }

    func testDocumentSearchFindsBodyOnlyNodes() {
        let node = makeNode(title: "Groceries", text: "Buy oat milk")
        let document = makeDocument(nodes: [node])
        XCTAssertEqual(document.search("oat").map(\.id), [node.id])
    }

    func testDocumentSearchIsCaseInsensitive() {
        let node = makeNode(title: "Quarterly REPORT")
        let document = makeDocument(nodes: [node])
        XCTAssertEqual(document.search("report").map(\.id), [node.id])
    }

    func testDocumentSearchEmptyQueryReturnsNothing() {
        let document = makeDocument(nodes: [makeNode(title: "Anything")])
        XCTAssertTrue(document.search("").isEmpty)
        XCTAssertTrue(document.search("   ").isEmpty)
    }

    func testDocumentSearchExcludesNonMatches() {
        let document = makeDocument(nodes: [makeNode(title: "Alpha"), makeNode(title: "Beta")])
        XCTAssertEqual(document.search("zzz").count, 0)
    }

    func testDocumentSearchRespectsLimit() {
        let nodes = (0..<10).map { makeNode(title: "Match \($0)") }
        let document = makeDocument(nodes: nodes)
        XCTAssertEqual(document.search("match", limit: 3).count, 3)
    }

    func testDocumentSearchUsesDisplayLabelForWindowNodes() {
        let reference = windowReference(windowTitle: "Design Review", appName: "Figma")
        let node = makeNode(kind: .window, title: "", windowReference: reference)
        let document = makeDocument(nodes: [node])
        XCTAssertEqual(document.search("review").map(\.id), [node.id])
    }
}
