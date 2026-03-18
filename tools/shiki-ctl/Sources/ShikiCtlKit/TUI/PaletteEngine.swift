import Foundation

// MARK: - PaletteSearchResult

public enum PaletteSearchResult: Sendable {
    case results([PaletteResult])
    case scopeChange(String)
}

// MARK: - PaletteEngine

public struct PaletteEngine: Sendable {
    public let sources: [any PaletteSource]

    public init(sources: [any PaletteSource]) {
        self.sources = sources
    }

    /// Search all sources, merge by score, return sorted results (best first).
    public func search(query: String) async -> [PaletteResult] {
        await withTaskGroup(of: [PaletteResult].self) { group in
            for source in sources {
                group.addTask {
                    await source.search(query: query)
                }
            }
            var allResults: [PaletteResult] = []
            for await results in group {
                allResults.append(contentsOf: results)
            }
            return allResults.sorted { $0.score < $1.score }
        }
    }

    /// Search with prefix mode detection.
    ///
    /// - `s:maya` searches only SessionSource with query "maya"
    /// - `@Sensei` searches only agent/persona source with query "Sensei"
    /// - `>status` searches only command source with query "status"
    /// - `#maya` returns a scope change (not results)
    /// - Anything else searches all sources
    public func searchWithPrefix(rawQuery: String) async -> PaletteSearchResult {
        // Scope change
        if rawQuery.hasPrefix("#") {
            let scope = String(rawQuery.dropFirst())
            return .scopeChange(scope)
        }

        // Check for prefix match against sources
        for source in sources {
            guard let sourcePrefix = source.prefix else { continue }
            if rawQuery.hasPrefix(sourcePrefix) {
                let query = String(rawQuery.dropFirst(sourcePrefix.count))
                let results = await source.search(query: query)
                return .results(results.sorted { $0.score < $1.score })
            }
        }

        // No prefix match — search all
        let results = await search(query: rawQuery)
        return .results(results)
    }
}
