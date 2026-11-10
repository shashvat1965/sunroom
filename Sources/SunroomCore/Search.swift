import Foundation

/// Simple, dependency-free fuzzy matcher for the command palette and find bar.
///
/// Scoring favors: exact prefix > word start > camel-case boundary > substring,
/// with a penalty for gaps. This is the same feel as Xcode's "Open Quickly".
public enum FuzzyMatcher {

    public struct Match {
        public let score: Int
        public let matchedRanges: [Range<Int>]
    }

    public static func score(query: String, candidate: String) -> Match? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Match(score: 0, matchedRanges: []) }
        let queryChars = Array(trimmed.lowercased())
        let candidateChars = Array(candidate.lowercased())
        guard queryChars.count <= candidateChars.count else { return nil }

        // Fast path: contiguous substring.
        if let range = candidate.lowercased().range(of: trimmed.lowercased()) {
            let start = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
            var bonus = 10
            if start == 0 { bonus = 24 }
            else if let index = candidate.index(candidate.startIndex, offsetBy: start, limitedBy: candidate.endIndex),
                    start > 0, candidate[candidate.index(before: index)] == " " {
                bonus = 18
            }
            return Match(score: 100 + bonus - min(start, 10), matchedRanges: [start..<(start + trimmed.count)])
        }

        var queryIndex = 0
        var score = 0
        var lastMatchIndex = -1
        var ranges: [Range<Int>] = []
        var rangeStart: Int?

        for (index, char) in candidateChars.enumerated() {
            guard queryIndex < queryChars.count else { break }
            if char == queryChars[queryIndex] {
                if lastMatchIndex == index - 1 {
                    score += 8
                    if let start = rangeStart {
                        ranges[ranges.count - 1] = start..<(index + 1)
                    } else {
                        rangeStart = index
                        ranges.append(index..<(index + 1))
                    }
                } else {
                    if let start = rangeStart { ranges[ranges.count - 1] = start..<(lastMatchIndex + 1) }
                    rangeStart = index
                    ranges.append(index..<(index + 1))
                    score += 3
                }
                if index == 0 { score += 12 }
                else {
                    let previous = candidateChars[index - 1]
                    if previous == " " || previous == "-" || previous == "_" || previous == "/" { score += 10 }
                    else if previous.isLowercase && char.isUppercase { score += 6 }
                }
                lastMatchIndex = index
                queryIndex += 1
            }
        }
        guard queryIndex == queryChars.count else { return nil }
        return Match(score: score, matchedRanges: ranges)
    }

    /// Ranks candidates, returning the best matches first with stable tie-breaking.
    public static func rank<T>(_ items: [T], query: String, key: (T) -> String) -> [T] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        return items
            .compactMap { item -> (T, Int)? in
                guard let match = score(query: query, candidate: key(item)) else { return nil }
                return (item, match.score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return key(lhs.0) < key(rhs.0)
            }
            .map(\.0)
    }
}

// MARK: - Document search

public struct NodeSearchHit: Sendable, Identifiable {
    public let id: UUID
    public let node: CanvasNode
    public let score: Int

    public init(node: CanvasNode, score: Int) {
        self.id = node.id
        self.node = node
        self.score = score
    }
}

public extension CanvasDocument {
    /// Finds nodes matching `query` in title and body text.
    func search(_ query: String, limit: Int = 40) -> [NodeSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var hits: [NodeSearchHit] = []
        for node in nodes {
            let titleMatch = FuzzyMatcher.score(query: trimmed, candidate: node.displayLabel)
            let bodyMatch = FuzzyMatcher.score(query: trimmed, candidate: node.text)
            let best = max(titleMatch?.score ?? -1, (bodyMatch.map { $0.score - 8 }) ?? -1)
            if best > 0 {
                hits.append(NodeSearchHit(node: node, score: best))
            }
        }
        return hits.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }
}
