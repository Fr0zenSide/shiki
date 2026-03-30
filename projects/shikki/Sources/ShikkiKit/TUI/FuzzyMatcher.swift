import Foundation

// MARK: - FuzzyMatch

public struct FuzzyMatch: Sendable {
    public let target: String
    public let score: Int
    public let matchedRanges: [Range<String.Index>]

    public init(target: String, score: Int, matchedRanges: [Range<String.Index>]) {
        self.target = target
        self.score = score
        self.matchedRanges = matchedRanges
    }
}

// MARK: - FuzzyMatcher

public enum FuzzyMatcher {

    /// Score a query against a target string.
    /// Returns nil if no match, or a FuzzyMatch with score (lower = better).
    ///
    /// Scoring rules:
    /// - Empty query = match everything with score 0
    /// - Exact match = 0
    /// - Prefix match = query.count (best substring)
    /// - Start-of-word match bonus (camelCase, snake_case boundaries)
    /// - Consecutive character matches score better than scattered
    /// - Case-insensitive matching, but exact case gets bonus
    public static func match(query: String, in target: String) -> FuzzyMatch? {
        // Empty query matches everything
        if query.isEmpty {
            return FuzzyMatch(target: target, score: 0, matchedRanges: [])
        }

        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        // Exact match
        if queryLower == targetLower {
            let casePenalty = (query == target) ? 0 : 1
            let fullRange = target.startIndex..<target.endIndex
            return FuzzyMatch(target: target, score: casePenalty, matchedRanges: [fullRange])
        }

        // Try to find all query characters in order
        guard let (positions, ranges) = findMatchPositions(queryLower: queryLower, targetLower: targetLower, target: target) else {
            return nil
        }

        let score = computeScore(
            query: query, queryLower: queryLower,
            target: target, targetLower: targetLower,
            positions: positions
        )

        return FuzzyMatch(target: target, score: score, matchedRanges: ranges)
    }

    /// Score and rank multiple targets, returning sorted results (best first).
    public static func rank(query: String, targets: [String]) -> [FuzzyMatch] {
        targets.compactMap { match(query: query, in: $0) }
            .sorted { $0.score < $1.score }
    }

    // MARK: - Private

    /// Find the best match positions for query characters in target.
    /// Uses a greedy approach that prefers word boundaries and consecutive matches.
    private static func findMatchPositions(
        queryLower: String, targetLower: String, target: String
    ) -> (positions: [String.Index], ranges: [Range<String.Index>])? {
        let boundaries = wordBoundaryIndices(target)
        var positions: [String.Index] = []
        var searchFrom = targetLower.startIndex

        for qChar in queryLower {
            // First try: find at a word boundary from current position
            var foundBoundary: String.Index?
            for boundary in boundaries {
                if boundary >= searchFrom,
                   boundary < targetLower.endIndex,
                   targetLower[boundary] == qChar {
                    foundBoundary = boundary
                    break
                }
            }

            if let boundary = foundBoundary {
                positions.append(boundary)
                searchFrom = targetLower.index(after: boundary)
                continue
            }

            // Fallback: find next occurrence from searchFrom
            guard let idx = targetLower[searchFrom...].firstIndex(of: qChar) else {
                return nil
            }
            positions.append(idx)
            searchFrom = targetLower.index(after: idx)
        }

        let ranges = collapseToRanges(positions, in: target)
        return (positions, ranges)
    }

    /// Compute the score for a match. Lower = better.
    private static func computeScore(
        query: String, queryLower: String,
        target: String, targetLower: String,
        positions: [String.Index]
    ) -> Int {
        guard !positions.isEmpty else { return 0 }

        let boundaries = Set(wordBoundaryIndices(target))
        var score = 0

        // Base: distance from start (prefix bonus)
        let firstPos = target.distance(from: target.startIndex, to: positions[0])
        score += firstPos * 3  // penalty for non-prefix match

        // Consecutive bonus — heavily reward contiguous runs
        var consecutiveRuns = 0
        var gapPenalty = 0
        for i in 1..<positions.count {
            let expected = target.index(after: positions[i - 1])
            if positions[i] == expected {
                consecutiveRuns += 1
            } else {
                let gap = target.distance(from: positions[i - 1], to: positions[i]) - 1
                gapPenalty += gap * 4  // heavy penalty per gap character
            }
        }

        score += gapPenalty
        score -= consecutiveRuns * 3  // strong reward for consecutive

        // Word boundary bonus
        var boundaryHits = 0
        for pos in positions {
            if boundaries.contains(pos) {
                boundaryHits += 1
            }
        }
        score -= boundaryHits * 2  // reward boundary matches

        // Case match bonus
        var caseMatches = 0
        let queryChars = Array(query)
        for (i, pos) in positions.enumerated() {
            if i < queryChars.count && target[pos] == queryChars[i] {
                caseMatches += 1
            }
        }
        score -= caseMatches  // reward exact case

        // Length penalty — longer targets score slightly worse
        score += max(0, target.count - query.count)

        // Ensure positive scores for non-exact matches
        return max(1, score)
    }

    /// Find word boundary indices: start of string, after _, after uppercase in camelCase.
    private static func wordBoundaryIndices(_ string: String) -> [String.Index] {
        var boundaries: [String.Index] = []
        guard !string.isEmpty else { return boundaries }

        // First character is always a boundary
        boundaries.append(string.startIndex)

        var prevIndex = string.startIndex
        var idx = string.index(after: string.startIndex)

        while idx < string.endIndex {
            let prev = string[prevIndex]
            let curr = string[idx]

            // After underscore or hyphen
            if prev == "_" || prev == "-" {
                boundaries.append(idx)
            }
            // camelCase boundary: lowercase followed by uppercase
            else if prev.isLowercase && curr.isUppercase {
                boundaries.append(idx)
            }
            // Transition from non-letter to letter
            else if !prev.isLetter && curr.isLetter {
                boundaries.append(idx)
            }

            prevIndex = idx
            idx = string.index(after: idx)
        }

        return boundaries
    }

    /// Collapse consecutive indices into ranges.
    private static func collapseToRanges(_ positions: [String.Index], in string: String) -> [Range<String.Index>] {
        guard !positions.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var rangeStart = positions[0]
        var rangeEnd = positions[0]

        for i in 1..<positions.count {
            let expected = string.index(after: rangeEnd)
            if positions[i] == expected {
                rangeEnd = positions[i]
            } else {
                ranges.append(rangeStart..<string.index(after: rangeEnd))
                rangeStart = positions[i]
                rangeEnd = positions[i]
            }
        }

        ranges.append(rangeStart..<string.index(after: rangeEnd))
        return ranges
    }
}
