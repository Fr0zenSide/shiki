import Testing
@testable import ShikiCtlKit

@Suite("FuzzyMatcher scoring")
struct FuzzyMatcherTests {

    @Test("Exact match scores 0")
    func exactMatch() {
        let result = FuzzyMatcher.match(query: "status", in: "status")
        #expect(result != nil)
        #expect(result!.score == 0)
    }

    @Test("Prefix match scores low")
    func prefixMatch() {
        let result = FuzzyMatcher.match(query: "sta", in: "status")
        #expect(result != nil)
        #expect(result!.score > 0)
        // Prefix should score better than scattered
        let scattered = FuzzyMatcher.match(query: "sts", in: "status")
        #expect(scattered != nil)
        #expect(result!.score < scattered!.score)
    }

    @Test("Substring match scores medium")
    func substringMatch() {
        let result = FuzzyMatcher.match(query: "atu", in: "status")
        #expect(result != nil)
        // Substring should score worse than or equal to prefix
        let prefix = FuzzyMatcher.match(query: "sta", in: "status")!
        #expect(result!.score >= prefix.score)
    }

    @Test("Scattered match scores higher")
    func scatteredMatch() {
        let result = FuzzyMatcher.match(query: "sts", in: "status")
        #expect(result != nil)
        // Scattered should score worse than consecutive substring
        let consecutive = FuzzyMatcher.match(query: "atu", in: "status")!
        #expect(result!.score > consecutive.score)
    }

    @Test("No match returns nil")
    func noMatch() {
        let result = FuzzyMatcher.match(query: "xyz", in: "status")
        #expect(result == nil)
    }

    @Test("Case insensitive matching")
    func caseInsensitive() {
        let result = FuzzyMatcher.match(query: "STATUS", in: "status")
        #expect(result != nil)
        // Exact case should get a bonus (lower score)
        let exactCase = FuzzyMatcher.match(query: "status", in: "status")!
        #expect(exactCase.score <= result!.score)
    }

    @Test("Start-of-word bonus for camelCase")
    func camelCaseBonus() {
        // "sR" matches start-of-word in "sessionRegistry" (s + R)
        let camel = FuzzyMatcher.match(query: "sR", in: "sessionRegistry")
        #expect(camel != nil)
        // Compare to matching non-boundary chars
        let nonBoundary = FuzzyMatcher.match(query: "eR", in: "sessionRegistry")
        #expect(nonBoundary != nil)
        #expect(camel!.score < nonBoundary!.score)
    }

    @Test("Start-of-word bonus for snake_case")
    func snakeCaseBonus() {
        // "s_r" boundary match in "session_registry"
        let snake = FuzzyMatcher.match(query: "sr", in: "session_registry")
        #expect(snake != nil)
        // "er" matches non-boundary
        let nonBoundary = FuzzyMatcher.match(query: "er", in: "session_registry")
        #expect(nonBoundary != nil)
        #expect(snake!.score < nonBoundary!.score)
    }

    @Test("Rank returns sorted results")
    func rankSorted() {
        let targets = ["status", "start", "statistics", "best"]
        let results = FuzzyMatcher.rank(query: "sta", targets: targets)
        // All should match except "best" (no 's' then 't' then 'a' in order... actually "best" has no match)
        #expect(results.count >= 3)
        // Results should be sorted by score ascending
        for i in 0..<(results.count - 1) {
            #expect(results[i].score <= results[i + 1].score)
        }
    }

    @Test("Empty query matches everything with score 0")
    func emptyQuery() {
        let result = FuzzyMatcher.match(query: "", in: "anything")
        #expect(result != nil)
        #expect(result!.score == 0)
    }

    @Test("Matched ranges are populated")
    func matchedRanges() {
        let result = FuzzyMatcher.match(query: "sta", in: "status")
        #expect(result != nil)
        #expect(!result!.matchedRanges.isEmpty)
    }
}

@Suite("PaletteEngine multi-source")
struct PaletteEngineTests {

    // MARK: - Mock Source

    struct MockSource: PaletteSource {
        let category: String
        let prefix: String?
        let items: [PaletteResult]

        func search(query: String) async -> [PaletteResult] {
            if query.isEmpty { return items }
            return items.compactMap { item in
                guard let match = FuzzyMatcher.match(query: query, in: item.title) else {
                    return nil
                }
                return PaletteResult(
                    id: item.id, title: item.title,
                    subtitle: item.subtitle, category: item.category,
                    icon: item.icon, score: match.score
                )
            }
        }
    }

    private func makeEngine() -> PaletteEngine {
        let sessionSource = MockSource(
            category: "session", prefix: "s:",
            items: [
                PaletteResult(id: "s1", title: "maya-onboarding", subtitle: "working", category: "session", icon: nil, score: 0),
                PaletteResult(id: "s2", title: "wabisabi-paywall", subtitle: "idle", category: "session", icon: nil, score: 0),
            ]
        )
        let commandSource = MockSource(
            category: "command", prefix: ">",
            items: [
                PaletteResult(id: "c1", title: "status", subtitle: "Show status", category: "command", icon: nil, score: 0),
                PaletteResult(id: "c2", title: "dispatch", subtitle: "Dispatch task", category: "command", icon: nil, score: 0),
            ]
        )
        let agentSource = MockSource(
            category: "agent", prefix: "@",
            items: [
                PaletteResult(id: "a1", title: "Sensei", subtitle: "CTO", category: "agent", icon: nil, score: 0),
                PaletteResult(id: "a2", title: "Hanami", subtitle: "UX", category: "agent", icon: nil, score: 0),
            ]
        )
        return PaletteEngine(sources: [sessionSource, commandSource, agentSource])
    }

    @Test("Search merges results from all sources")
    func mergeResults() async {
        let engine = makeEngine()
        let results = await engine.search(query: "")
        // Should have results from all 3 sources
        let categories = Set(results.map(\.category))
        #expect(categories.contains("session"))
        #expect(categories.contains("command"))
        #expect(categories.contains("agent"))
    }

    @Test("Prefix s: filters to session source only")
    func sessionPrefix() async {
        let engine = makeEngine()
        let searchResult = await engine.searchWithPrefix(rawQuery: "s:maya")
        guard case .results(let results) = searchResult else {
            Issue.record("Expected results, got scope change")
            return
        }
        #expect(results.allSatisfy { $0.category == "session" })
        #expect(!results.isEmpty)
    }

    @Test("Prefix @ filters to agent source only")
    func agentPrefix() async {
        let engine = makeEngine()
        let searchResult = await engine.searchWithPrefix(rawQuery: "@Sensei")
        guard case .results(let results) = searchResult else {
            Issue.record("Expected results, got scope change")
            return
        }
        #expect(results.allSatisfy { $0.category == "agent" })
    }

    @Test("Prefix > filters to command source only")
    func commandPrefix() async {
        let engine = makeEngine()
        let searchResult = await engine.searchWithPrefix(rawQuery: ">status")
        guard case .results(let results) = searchResult else {
            Issue.record("Expected results, got scope change")
            return
        }
        #expect(results.allSatisfy { $0.category == "command" })
    }

    @Test("# prefix returns scope change")
    func scopeChange() async {
        let engine = makeEngine()
        let searchResult = await engine.searchWithPrefix(rawQuery: "#maya")
        guard case .scopeChange(let scope) = searchResult else {
            Issue.record("Expected scope change, got results")
            return
        }
        #expect(scope == "maya")
    }

    @Test("Empty query returns all results")
    func emptyQuery() async {
        let engine = makeEngine()
        let results = await engine.search(query: "")
        #expect(results.count == 6) // 2 sessions + 2 commands + 2 agents
    }

    @Test("Results sorted by score across sources")
    func sortedByScore() async {
        let engine = makeEngine()
        let results = await engine.search(query: "s")
        // All results should be sorted by score ascending
        for i in 0..<(results.count - 1) {
            #expect(results[i].score <= results[i + 1].score)
        }
    }
}
